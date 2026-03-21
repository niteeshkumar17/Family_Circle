const { onValueUpdated } = require('firebase-functions/v2/database');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getDatabase } = require('firebase-admin/database');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
const rtdb = getDatabase();
const messaging = getMessaging();

// ============== GEOFENCE DETECTION ==============

/**
 * Triggered when a user's location is updated in Realtime Database
 * Checks if the user has entered or exited any geofences
 */
exports.checkGeofences = onValueUpdated(
  '/locations/{familyId}/{userId}',
  async (event) => {
    const { familyId, userId } = event.params;
    const newLocation = event.data.after.val();
    const oldLocation = event.data.before.val();

    // Skip if location hasn't changed significantly
    if (oldLocation &&
      Math.abs(newLocation.latitude - oldLocation.latitude) < 0.0001 &&
      Math.abs(newLocation.longitude - oldLocation.longitude) < 0.0001) {
      return null;
    }

    // Get all active geofences for this family
    const geofencesSnap = await db
      .collection('families')
      .doc(familyId)
      .collection('geofences')
      .where('isActive', '==', true)
      .get();

    if (geofencesSnap.empty) return null;

    // Get user info
    const userSnap = await db.collection('users').doc(userId).get();
    const userName = userSnap.exists ? userSnap.data().displayName : 'A family member';

    // Check each geofence
    for (const geofenceDoc of geofencesSnap.docs) {
      const geofence = geofenceDoc.data();

      // Check if user is monitored by this geofence
      if (geofence.monitoredMembers &&
        geofence.monitoredMembers.length > 0 &&
        !geofence.monitoredMembers.includes(userId)) {
        continue;
      }

      const distance = calculateDistance(
        newLocation.latitude, newLocation.longitude,
        geofence.latitude, geofence.longitude
      );

      const isInside = distance <= geofence.radiusMeters;

      // Get previous state
      const stateRef = rtdb.ref(`geofence_states/${familyId}/${userId}/${geofenceDoc.id}`);
      const stateSnap = await stateRef.get();
      const wasInside = stateSnap.val() || false;

      if (isInside !== wasInside) {
        // State changed - create event
        const eventType = isInside ? 'entry' : 'exit';

        // Check quiet hours
        if (!isInQuietHours(geofence.settings)) {
          // Create geofence event
          await db.collection('families').doc(familyId)
            .collection('geofence_events').add({
              geofenceId: geofenceDoc.id,
              geofenceName: geofence.name,
              userId: userId,
              userName: userName,
              eventType: eventType,
              timestamp: FieldValue.serverTimestamp(),
              latitude: newLocation.latitude,
              longitude: newLocation.longitude,
            });

          // Send notifications to admins
          await sendGeofenceNotification(familyId, userId, userName, geofence, eventType);
        }

        // Update state
        await stateRef.set(isInside);
      }
    }

    return null;
  }
);

// ============== SOS BROADCAST ==============

/**
 * Triggered when a new SOS event is created
 * Sends emergency notifications to all family members
 */
exports.broadcastSOS = onDocumentCreated('sos_events/{eventId}', async (event) => {
  const sosEvent = event.data.data();
  const eventId = event.params.eventId;

  // Get all family members except the SOS sender
  const membersSnap = await db
    .collection('families')
    .doc(sosEvent.familyId)
    .collection('members')
    .get();

  const tokens = [];
  const notificationPromises = [];

  for (const memberDoc of membersSnap.docs) {
    if (memberDoc.id === sosEvent.userId) continue;

    const userSnap = await db.collection('users').doc(memberDoc.id).get();
    if (userSnap.exists && userSnap.data().deviceInfo?.fcmToken) {
      tokens.push(userSnap.data().deviceInfo.fcmToken);
    }

    // Create notification document
    notificationPromises.push(
      db.collection('notifications').doc(memberDoc.id)
        .collection('items').add({
          type: 'sos',
          title: '🚨 SOS EMERGENCY',
          body: `${sosEvent.userName} needs help!`,
          data: {
            eventId: eventId,
            userId: sosEvent.userId,
            latitude: sosEvent.triggerLocation?.latitude?.toString() || '',
            longitude: sosEvent.triggerLocation?.longitude?.toString() || '',
          },
          createdAt: FieldValue.serverTimestamp(),
          isRead: false,
          priority: 'urgent',
        })
    );
  }

  // Send FCM notifications
  if (tokens.length > 0) {
    await messaging.sendEachForMulticast({
      tokens: tokens,
      notification: {
        title: '🚨 SOS EMERGENCY',
        body: `${sosEvent.userName} needs help!`,
      },
      data: {
        type: 'sos',
        eventId: eventId,
        userId: sosEvent.userId,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'sos_alerts',
          priority: 'max',
          sound: 'sos_alarm',
          defaultVibrateTimings: false,
          vibrateTimingsMillis: [0, 500, 250, 500, 250, 500],
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'sos_alarm.wav',
            badge: 1,
            contentAvailable: true,
          },
        },
      },
    });
  }

  await Promise.all(notificationPromises);

  return null;
});

// ============== LOW BATTERY ALERT ==============

/**
 * Triggered when a user's location is updated
 * Checks if battery is low and sends alert
 */
exports.checkLowBattery = onValueUpdated(
  '/locations/{familyId}/{userId}',
  async (event) => {
    const { familyId, userId } = event.params;
    const newData = event.data.after.val();
    const oldData = event.data.before.val();

    // Check if battery just dropped below threshold
    const threshold = 20;
    if (newData.battery <= threshold && (!oldData || oldData.battery > threshold)) {
      const userSnap = await db.collection('users').doc(userId).get();
      const userName = userSnap.exists ? userSnap.data().displayName : 'A family member';

      // Get admin members
      const adminsSnap = await db
        .collection('families')
        .doc(familyId)
        .collection('members')
        .where('role', '==', 'admin')
        .get();

      const tokens = [];
      for (const adminDoc of adminsSnap.docs) {
        if (adminDoc.id === userId) continue;

        const adminUserSnap = await db.collection('users').doc(adminDoc.id).get();
        if (adminUserSnap.exists && adminUserSnap.data().deviceInfo?.fcmToken) {
          tokens.push(adminUserSnap.data().deviceInfo.fcmToken);
        }
      }

      if (tokens.length > 0) {
        await messaging.sendEachForMulticast({
          tokens: tokens,
          notification: {
            title: '🔋 Low Battery Alert',
            body: `${userName}'s phone is at ${newData.battery}%`,
          },
          data: {
            type: 'lowBattery',
            userId: userId,
            batteryLevel: newData.battery.toString(),
          },
          android: {
            notification: {
              channelId: 'system_alerts',
            },
          },
        });
      }
    }

    return null;
  }
);

// ============== FAMILY INVITE ==============

/**
 * Generates a unique invite code for a family
 */
exports.generateInviteCode = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be logged in');
  }

  const { familyId } = request.data;

  // Check if user is admin
  const memberSnap = await db
    .collection('families')
    .doc(familyId)
    .collection('members')
    .doc(request.auth.uid)
    .get();

  if (!memberSnap.exists || memberSnap.data().role !== 'admin') {
    throw new HttpsError('permission-denied', 'Only admins can generate invite codes');
  }

  // Generate unique code
  const inviteCode = generateRandomCode(6);
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 7); // Expires in 7 days

  await db.collection('invites').doc(inviteCode).set({
    familyId: familyId,
    createdBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: expiresAt,
    usedCount: 0,
    maxUses: 10,
  });

  return {
    inviteCode: inviteCode,
    inviteLink: `https://familynest.app/invite/${inviteCode}`,
    expiresAt: expiresAt.toISOString(),
  };
});

// ============== CLEANUP FUNCTIONS ==============

/**
 * Cleanup expired invites
 * Runs daily at 4 AM UTC
 */
exports.cleanupExpiredInvites = onSchedule('0 4 * * *', async (event) => {
  const now = new Date();

  const expiredInvites = await db
    .collection('invites')
    .where('expiresAt', '<', now)
    .get();

  const batch = db.batch();
  expiredInvites.forEach((doc) => {
    batch.delete(doc.ref);
  });

  await batch.commit();
  console.log(`Deleted ${expiredInvites.size} expired invites`);
  return null;
});

// ============== HELPER FUNCTIONS ==============

function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg) {
  return deg * (Math.PI / 180);
}

function isInQuietHours(settings) {
  if (!settings || !settings.enableQuietHours || !settings.quietStart || !settings.quietEnd) {
    return false;
  }

  const now = new Date();
  const currentMinutes = now.getHours() * 60 + now.getMinutes();
  const startMinutes = settings.quietStart.hour * 60 + settings.quietStart.minute;
  const endMinutes = settings.quietEnd.hour * 60 + settings.quietEnd.minute;

  if (startMinutes <= endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  } else {
    return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
  }
}

function generateRandomCode(length) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed ambiguous chars
  let code = '';
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

async function sendGeofenceNotification(familyId, userId, userName, geofence, eventType) {
  const action = eventType === 'entry' ? 'arrived at' : 'left';

  // Get admin tokens
  const adminsSnap = await db
    .collection('families')
    .doc(familyId)
    .collection('members')
    .where('role', '==', 'admin')
    .get();

  const tokens = [];
  for (const adminDoc of adminsSnap.docs) {
    if (adminDoc.id === userId) continue;

    const userSnap = await db.collection('users').doc(adminDoc.id).get();
    if (userSnap.exists && userSnap.data().deviceInfo?.fcmToken) {
      tokens.push(userSnap.data().deviceInfo.fcmToken);
    }
  }

  if (tokens.length > 0) {
    await messaging.sendEachForMulticast({
      tokens: tokens,
      notification: {
        title: eventType === 'entry' ? '📍 Arrival' : '🚶 Departure',
        body: `${userName} ${action} ${geofence.name}`,
      },
      data: {
        type: eventType === 'entry' ? 'geofenceEntry' : 'geofenceExit',
        userId: userId,
        geofenceName: geofence.name,
      },
      android: {
        notification: {
          channelId: 'geofence_alerts',
        },
      },
    });
  }
}
