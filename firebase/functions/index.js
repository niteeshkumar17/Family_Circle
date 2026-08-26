const { onValueUpdated } = require('firebase-functions/v2/database');
const {
  onDocumentCreated,
  onDocumentDeleted,
} = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const crypto = require('node:crypto');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getDatabaseWithUrl } = require('firebase-admin/database');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

// The CLI analyses this file with a FIREBASE_CONFIG that has no databaseURL, so
// resolving the instance implicitly fails at deploy time. Name it explicitly.
const DATABASE_URL = process.env.FIREBASE_DATABASE_URL ||
  'https://familynest-ec590-default-rtdb.firebaseio.com';

const db = getFirestore();
const rtdb = getDatabaseWithUrl(DATABASE_URL);
const messaging = getMessaging();

// Must match AppConfig in lib/config/app_config.dart.
const GEOFENCE_HYSTERESIS_METERS = 20;
const GEOFENCE_DEFAULT_DWELL_SECONDS = 180;
const LOCATION_HISTORY_DAYS = 30;

const LOW_BATTERY_THRESHOLD = 20;
// Do not re-alert about the same phone more often than this.
const LOW_BATTERY_COOLDOWN_MS = 6 * 60 * 60 * 1000;

// A tracker that has not published for this long has almost certainly been
// killed by the OS rather than merely throttled: the client's own watchdog
// publishes at least every few minutes while it is alive.
const TRACKER_STALE_MS = 20 * 60 * 1000;
// Minimum gap between wake-up pushes to the same device.
const WAKE_COOLDOWN_MS = 20 * 60 * 1000;
// After this many consecutive failures the device is treated as switched off
// or out of coverage, and retries drop to the longer interval below.
const WAKE_GIVE_UP_AFTER = 4;
const WAKE_BACKOFF_MS = 2 * 60 * 60 * 1000;

// ============== LOCATION TRIGGER ==============

/**
 * Single entry point for everything that reacts to a location write.
 *
 * Geofence evaluation and the low-battery check used to be two separate
 * triggers on the same path, which doubled the invocation cost of every
 * location update.
 */
exports.onLocationUpdated = onValueUpdated(
  '/locations/{familyId}/{userId}',
  async (event) => {
    const { familyId, userId } = event.params;
    const newLocation = event.data.after.val();
    const oldLocation = event.data.before.val();

    if (!newLocation || typeof newLocation !== 'object') {
      return null;
    }

    const userName = await getDisplayName(userId);

    await Promise.all([
      evaluateGeofences(familyId, userId, userName, newLocation, oldLocation),
      checkLowBattery(familyId, userId, userName, newLocation),
    ]);

    return null;
  }
);

async function evaluateGeofences(familyId, userId, userName, newLocation, oldLocation) {
  const latitude = toFiniteNumber(newLocation.latitude);
  const longitude = toFiniteNumber(newLocation.longitude);

  if (latitude === null || longitude === null) {
    return;
  }

  // Skip jitter: roughly 11 m at the equator.
  if (oldLocation &&
    Math.abs(latitude - toFiniteNumber(oldLocation.latitude)) < 0.0001 &&
    Math.abs(longitude - toFiniteNumber(oldLocation.longitude)) < 0.0001) {
    return;
  }

  const geofencesSnap = await db
    .collection('families')
    .doc(familyId)
    .collection('geofences')
    .where('isActive', '==', true)
    .get();

  if (geofencesSnap.empty) return;

  for (const geofenceDoc of geofencesSnap.docs) {
    const geofence = geofenceDoc.data() || {};
    const settings = geofence.settings || {};

    if (Array.isArray(geofence.monitoredMembers) &&
      geofence.monitoredMembers.length > 0 &&
      !geofence.monitoredMembers.includes(userId)) {
      continue;
    }

    const centerLat = toFiniteNumber(geofence.latitude);
    const centerLng = toFiniteNumber(geofence.longitude);
    const radius = toFiniteNumber(geofence.radiusMeters);

    if (centerLat === null || centerLng === null || radius === null) {
      console.warn('Skipping malformed geofence', {
        familyId,
        geofenceId: geofenceDoc.id,
      });
      continue;
    }

    const distance = calculateDistance(latitude, longitude, centerLat, centerLng);

    const stateRef = rtdb.ref(`geofence_states/${familyId}/${userId}/${geofenceDoc.id}`);
    const state = normalizeGeofenceState((await stateRef.get()).val());

    // A cushion around the boundary keeps a member who is parked on the edge
    // from generating an endless stream of entry/exit alerts.
    const isInside = state.inside
      ? distance <= radius + GEOFENCE_HYSTERESIS_METERS
      : distance <= radius - GEOFENCE_HYSTERESIS_METERS;

    const now = Date.now();

    if (isInside !== state.inside) {
      const eventType = isInside ? 'entry' : 'exit';
      const wantsNotification = isInside
        ? settings.notifyOnEntry !== false
        : settings.notifyOnExit !== false;
      const notify = wantsNotification && !isInQuietHours(settings);

      await recordGeofenceEvent({
        familyId,
        geofenceId: geofenceDoc.id,
        geofence,
        userId,
        userName,
        eventType,
        latitude,
        longitude,
        notificationSent: notify,
      });

      if (notify) {
        await sendGeofenceNotification(familyId, userId, userName, geofence, eventType);
      }

      await stateRef.set({
        inside: isInside,
        since: now,
        dwellNotified: false,
      });
      continue;
    }

    // Still inside: fire the dwell alert once the member has stayed long enough.
    const dwellSeconds = toFiniteNumber(settings.dwellTimeSeconds) > 0
      ? settings.dwellTimeSeconds
      : GEOFENCE_DEFAULT_DWELL_SECONDS;

    if (isInside &&
      settings.notifyOnDwell !== false &&
      !state.dwellNotified &&
      state.since > 0 &&
      now - state.since >= dwellSeconds * 1000) {
      const notify = !isInQuietHours(settings);

      await recordGeofenceEvent({
        familyId,
        geofenceId: geofenceDoc.id,
        geofence,
        userId,
        userName,
        eventType: 'dwell',
        latitude,
        longitude,
        notificationSent: notify,
      });

      if (notify) {
        await sendGeofenceNotification(familyId, userId, userName, geofence, 'dwell');
      }

      await stateRef.update({ dwellNotified: true });
    }
  }
}

async function checkLowBattery(familyId, userId, userName, newData) {
  const battery = toFiniteNumber(newData.battery);
  if (battery === null || battery > LOW_BATTERY_THRESHOLD) {
    return;
  }

  const alertRef = rtdb.ref(`low_battery_alerts/${familyId}/${userId}`);
  const lastAlertAt = toFiniteNumber((await alertRef.get()).val()) || 0;
  const now = Date.now();

  // Charging cycles push the battery back and forth across the threshold, so a
  // cooldown rather than a simple edge check is what keeps this from spamming.
  if (now - lastAlertAt < LOW_BATTERY_COOLDOWN_MS) {
    return;
  }

  const recipientIds = await getNotifiableAdminIds(familyId, userId);
  if (recipientIds.length === 0) return;

  const title = '🔋 Low Battery Alert';
  const body = `${userName}'s phone is at ${battery}%`;

  await Promise.all([
    alertRef.set(now),
    saveInAppNotifications(recipientIds, {
      type: 'lowBattery',
      title,
      body,
      data: {
        userId: userId,
        familyId: familyId,
        batteryLevel: String(battery),
      },
    }),
    pushToUsers(recipientIds, {
      notification: { title, body },
      data: {
        type: 'lowBattery',
        userId: userId,
        familyId: familyId,
        batteryLevel: String(battery),
      },
      android: { notification: { channelId: 'system_alerts' } },
    }),
  ]);
}

// ============== SOS BROADCAST ==============

/**
 * Triggered when a new SOS event is created
 * Sends emergency notifications to all family members
 */
exports.broadcastSOS = onDocumentCreated('sos_events/{eventId}', async (event) => {
  if (!event.data) {
    return null;
  }

  const sosEvent = event.data.data();
  const eventId = event.params.eventId;

  if (!sosEvent?.familyId || !sosEvent?.userId) {
    console.warn('Skipping SOS broadcast due to missing required fields', { eventId });
    return null;
  }

  const membersSnap = await db
    .collection('families')
    .doc(sosEvent.familyId)
    .collection('members')
    .get();

  const recipientIds = membersSnap.docs
    .map((memberDoc) => memberDoc.id)
    .filter((memberId) => memberId !== sosEvent.userId);

  if (recipientIds.length === 0) {
    return null;
  }

  const title = '🚨 SOS EMERGENCY';
  const body = `${sosEvent.userName || 'A family member'} needs help!`;
  const latitude = sosEvent.triggerLocation?.latitude?.toString() || '';
  const longitude = sosEvent.triggerLocation?.longitude?.toString() || '';

  await Promise.all([
    saveInAppNotifications(recipientIds, {
      type: 'sos',
      title,
      body,
      priority: 'urgent',
      data: {
        eventId: eventId,
        userId: sosEvent.userId,
        familyId: sosEvent.familyId,
        latitude,
        longitude,
      },
    }),
    pushToUsers(recipientIds, {
      notification: { title, body },
      data: {
        type: 'sos',
        eventId: eventId,
        userId: sosEvent.userId,
        familyId: sosEvent.familyId,
        latitude,
        longitude,
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
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            sound: 'sos_alarm.wav',
            badge: 1,
            contentAvailable: true,
          },
        },
      },
    }),
  ]);

  return null;
});

// ============== FAMILY INVITE ==============

/**
 * Generates a unique invite code for a family
 */
exports.generateInviteCode = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be logged in');
  }

  const { familyId } = request.data || {};

  if (!familyId) {
    throw new HttpsError('invalid-argument', 'familyId is required');
  }

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

  // Use the same invite code flow as the mobile app: families/{familyId}.inviteCode
  const inviteCode = await generateUniqueFamilyInviteCode(6);
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24h

  await db.collection('families').doc(familyId).update({
    inviteCode: inviteCode,
    inviteCodeExpiresAt: expiresAt,
    inviteCodeGeneratedBy: request.auth.uid,
    inviteCodeGeneratedAt: FieldValue.serverTimestamp(),
  });

  return {
    inviteCode: inviteCode,
    inviteLink: `https://familynest.app/invite/${inviteCode}`,
    expiresAt: expiresAt.toISOString(),
  };
});

// ============== MEMBERSHIP MIRRORING & CLEANUP ==============

/**
 * Mirrors membership into Realtime Database so that the database rules can
 * scope reads to a member's own families without a Firestore lookup.
 */
exports.onMemberAdded = onDocumentCreated(
  'families/{familyId}/members/{userId}',
  async (event) => {
    const { familyId, userId } = event.params;
    await rtdb.ref(`family_members/${familyId}/${userId}`).set(true);
    return null;
  }
);

/**
 * A member cannot clean up another member's data from the client: the security
 * rules only let a user write their own location. Removal is therefore
 * finished here with admin privileges.
 */
exports.onMemberRemoved = onDocumentDeleted(
  'families/{familyId}/members/{userId}',
  async (event) => {
    const { familyId, userId } = event.params;

    await Promise.all([
      rtdb.ref(`family_members/${familyId}/${userId}`).remove(),
      rtdb.ref(`locations/${familyId}/${userId}`).remove(),
      rtdb.ref(`locationHistory/${familyId}/${userId}`).remove(),
      rtdb.ref(`geofence_states/${familyId}/${userId}`).remove(),
      rtdb.ref(`low_battery_alerts/${familyId}/${userId}`).remove(),
      detachUserFromFamily(userId, familyId),
    ]);

    return null;
  }
);

/**
 * Deletes the data that a client cannot reach once the family document is gone.
 */
exports.onFamilyDeleted = onDocumentDeleted('families/{familyId}', async (event) => {
  const { familyId } = event.params;

  const memberIds = Object.keys(
    (await rtdb.ref(`family_members/${familyId}`).get()).val() || {}
  );

  await Promise.all([
    rtdb.ref(`family_members/${familyId}`).remove(),
    rtdb.ref(`locations/${familyId}`).remove(),
    rtdb.ref(`locationHistory/${familyId}`).remove(),
    rtdb.ref(`geofence_states/${familyId}`).remove(),
    rtdb.ref(`low_battery_alerts/${familyId}`).remove(),
    rtdb.ref(`sos_active/${familyId}`).remove(),
    ...memberIds.map((userId) => detachUserFromFamily(userId, familyId)),
  ]);

  await Promise.all([
    deleteSubcollection(db.collection('families').doc(familyId).collection('geofences')),
    deleteSubcollection(db.collection('families').doc(familyId).collection('geofence_events')),
  ]);

  return null;
});

// ============== CLEANUP FUNCTIONS ==============

/**
 * Cleanup expired invites
 * Runs daily at 4 AM UTC
 */
exports.cleanupExpiredInvites = onSchedule('0 4 * * *', async () => {
  const now = new Date();
  const pageSize = 400;
  let totalCleared = 0;

  while (true) {
    const expiredInvites = await db
      .collection('families')
      .where('inviteCodeExpiresAt', '<', now)
      .limit(pageSize)
      .get();

    if (expiredInvites.empty) {
      break;
    }

    const batch = db.batch();
    expiredInvites.docs.forEach((doc) => {
      batch.update(doc.ref, {
        inviteCode: FieldValue.delete(),
        inviteCodeExpiresAt: FieldValue.delete(),
      });
    });

    await batch.commit();
    totalCleared += expiredInvites.size;

    if (expiredInvites.size < pageSize) {
      break;
    }
  }

  console.log(`Cleared ${totalCleared} expired family invite codes`);
  return null;
});

/**
 * Drops location breadcrumbs older than the advertised retention window.
 * History is bucketed per day (locationHistory/{familyId}/{userId}/{yyyy-MM-dd}),
 * so pruning is a matter of removing the stale day buckets.
 *
 * Runs daily at 3:30 AM UTC.
 */
exports.pruneLocationHistory = onSchedule('30 3 * * *', async () => {
  const cutoff = new Date(Date.now() - LOCATION_HISTORY_DAYS * 24 * 60 * 60 * 1000);
  const cutoffKey = cutoff.toISOString().slice(0, 10); // yyyy-MM-dd sorts lexically
  const families = (await rtdb.ref('locationHistory').get()).val() || {};

  let removed = 0;

  for (const [familyId, members] of Object.entries(families)) {
    for (const [userId, days] of Object.entries(members || {})) {
      const staleDays = Object.keys(days || {}).filter((dayKey) => dayKey < cutoffKey);
      if (staleDays.length === 0) continue;

      const updates = {};
      staleDays.forEach((dayKey) => {
        updates[dayKey] = null;
      });

      await rtdb.ref(`locationHistory/${familyId}/${userId}`).update(updates);
      removed += staleDays.length;
    }
  }

  console.log(`Pruned ${removed} stale location history buckets`);
  return null;
});

/**
 * Removes read in-app notifications older than 30 days.
 * Runs daily at 3 AM UTC.
 */
exports.cleanupOldNotifications = onSchedule('0 3 * * *', async () => {
  const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const stale = await db
    .collectionGroup('items')
    .where('createdAt', '<', cutoff)
    .limit(500)
    .get();

  if (stale.empty) return null;

  const batch = db.batch();
  stale.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  console.log(`Deleted ${stale.size} stale notifications`);
  return null;
});

// ============== TRACKER REVIVAL ==============

/**
 * Wakes devices whose location has gone stale.
 *
 * Manufacturer power managers (MIUI's cleaner, Samsung's app sleep, and their
 * equivalents) force stop the location foreground service even when the app
 * holds a battery-optimisation exemption, and Android does not restart it
 * afterwards. Left alone the device silently reports an hours-old position
 * until someone opens the app.
 *
 * A data-only high priority message is the remedy: it is delivered to a
 * process that was killed but not force stopped by the user, shows nothing,
 * and buys the app a short allowlist window in which it may restart a location
 * foreground service. The client handles it in firebaseMessagingBackgroundHandler.
 *
 * Runs every 15 minutes.
 */
exports.wakeStaleTrackers = onSchedule('*/15 * * * *', async () => {
  const now = Date.now();
  const families = (await rtdb.ref('locations').get()).val() || {};

  // A user can share with several nests; the freshest write across all of them
  // decides whether their device is actually stale.
  const freshestByUser = new Map();

  for (const members of Object.values(families)) {
    for (const [userId, location] of Object.entries(members || {})) {
      // Sharing that was deliberately paused is not a fault to repair.
      if (!location || location.isActive === false) continue;
      const timestamp = toFiniteNumber(location.timestamp) || 0;
      const previous = freshestByUser.get(userId) || 0;
      if (timestamp > previous) freshestByUser.set(userId, timestamp);
    }
  }

  const stale = Array.from(freshestByUser.entries())
    .filter(([, timestamp]) => now - timestamp > TRACKER_STALE_MS);

  if (stale.length === 0) return null;

  const attempts = (await rtdb.ref('wakeAttempts').get()).val() || {};
  const toWake = [];
  const attemptUpdates = {};

  for (const [userId, timestamp] of stale) {
    const record = attempts[userId] || {};
    const lastAttempt = toFiniteNumber(record.lastAttempt) || 0;

    // A newer position than the one that triggered the last attempt means the
    // device came back, so the failure streak starts again from zero.
    const recovered = timestamp > (toFiniteNumber(record.staleSince) || 0);
    const consecutive = recovered ? 0 : (toFiniteNumber(record.consecutive) || 0);

    const cooldown = consecutive >= WAKE_GIVE_UP_AFTER
      ? WAKE_BACKOFF_MS
      : WAKE_COOLDOWN_MS;

    if (now - lastAttempt < cooldown) continue;

    toWake.push(userId);
    attemptUpdates[userId] = {
      lastAttempt: now,
      staleSince: timestamp,
      consecutive: consecutive + 1,
    };
  }

  if (toWake.length === 0) return null;

  await pushToUsers(toWake, {
    // No `notification` block: this must stay invisible to the user.
    data: {
      type: 'wake_tracker',
      sentAt: String(now),
    },
    android: {
      priority: 'high',
    },
    apns: {
      headers: {
        'apns-priority': '5',
        'apns-push-type': 'background',
      },
      payload: {
        aps: { 'content-available': 1 },
      },
    },
  });

  await rtdb.ref('wakeAttempts').update(attemptUpdates);

  console.log(`Sent wake-up push to ${toWake.length} stale tracker(s)`);
  return null;
});

// ============== HELPER FUNCTIONS ==============

function toFiniteNumber(value) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeGeofenceState(raw) {
  // Older builds stored a plain boolean at this path.
  if (typeof raw === 'boolean') {
    return { inside: raw, since: 0, dwellNotified: false };
  }
  if (!raw || typeof raw !== 'object') {
    return { inside: false, since: 0, dwellNotified: false };
  }
  return {
    inside: raw.inside === true,
    since: toFiniteNumber(raw.since) || 0,
    dwellNotified: raw.dwellNotified === true,
  };
}

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
    code += chars.charAt(crypto.randomInt(0, chars.length));
  }
  return code;
}

async function generateUniqueFamilyInviteCode(length) {
  const maxAttempts = 10;

  for (let i = 0; i < maxAttempts; i++) {
    const code = generateRandomCode(length);
    const existing = await db
      .collection('families')
      .where('inviteCode', '==', code)
      .limit(1)
      .get();

    if (existing.empty) {
      return code;
    }
  }

  throw new HttpsError('internal', 'Failed to generate a unique invite code');
}

async function getDisplayName(userId) {
  const userSnap = await db.collection('users').doc(userId).get();
  if (!userSnap.exists) return 'A family member';
  const data = userSnap.data() || {};
  return data.displayName || data.name || 'A family member';
}

async function detachUserFromFamily(userId, familyId) {
  const userRef = db.collection('users').doc(userId);

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists) return;

      const updates = {
        familyIds: FieldValue.arrayRemove(familyId),
      };
      if (snap.data()?.currentFamilyId === familyId) {
        const remaining = (snap.data()?.familyIds || [])
          .filter((id) => id !== familyId);
        updates.currentFamilyId = remaining[0] || null;
      }

      tx.update(userRef, updates);
    });
  } catch (error) {
    console.error('Failed to detach user from family', { userId, familyId, error });
  }
}

async function deleteSubcollection(collectionRef) {
  const pageSize = 400;

  while (true) {
    const snap = await collectionRef.limit(pageSize).get();
    if (snap.empty) return;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    if (snap.size < pageSize) return;
  }
}

async function recordGeofenceEvent({
  familyId,
  geofenceId,
  geofence,
  userId,
  userName,
  eventType,
  latitude,
  longitude,
  notificationSent,
}) {
  await db.collection('families').doc(familyId)
    .collection('geofence_events').add({
      geofenceId,
      geofenceName: geofence.name || 'a place',
      userId,
      userName,
      eventType,
      timestamp: FieldValue.serverTimestamp(),
      latitude,
      longitude,
      notificationSent,
    });
}

/**
 * Admins that should hear about a family event, honouring the per-geofence
 * `notifyMembers` allow-list when one is configured.
 */
async function getNotifiableAdminIds(familyId, excludeUserId, notifyMembers) {
  const adminsSnap = await db
    .collection('families')
    .doc(familyId)
    .collection('members')
    .where('role', '==', 'admin')
    .get();

  return adminsSnap.docs
    .map((adminDoc) => adminDoc.id)
    .filter((adminId) => adminId !== excludeUserId)
    .filter((adminId) => !Array.isArray(notifyMembers) ||
      notifyMembers.length === 0 ||
      notifyMembers.includes(adminId));
}

/**
 * Writes the in-app notification list entries. The path must stay in sync with
 * NotificationService in the Flutter app.
 */
async function saveInAppNotifications(userIds, { type, title, body, data, priority }) {
  if (userIds.length === 0) return;

  const batch = db.batch();

  userIds.forEach((userId) => {
    const ref = db.collection('notifications').doc(userId).collection('items').doc();
    batch.set(ref, {
      type,
      title,
      body,
      data: data || {},
      createdAt: FieldValue.serverTimestamp(),
      isRead: false,
      priority: priority || 'normal',
    });
  });

  await batch.commit();
}

async function pushToUsers(userIds, message) {
  if (userIds.length === 0) return;

  const userSnaps = await Promise.all(
    userIds.map((userId) => db.collection('users').doc(userId).get())
  );

  const tokenEntries = userSnaps
    .map((userSnap, index) => {
      const data = userSnap.data() || {};
      const token = data.deviceInfo?.fcmToken || data.fcmToken;
      return token ? { userId: userIds[index], token } : null;
    })
    .filter(Boolean);

  if (tokenEntries.length === 0) return;

  const batchResponse = await messaging.sendEachForMulticast({
    ...message,
    tokens: tokenEntries.map((entry) => entry.token),
  });

  await cleanupInvalidFcmTokens(tokenEntries, batchResponse);
}

function isStaleFcmError(error) {
  const code = error?.code;
  return code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/invalid-registration-token';
}

async function cleanupInvalidFcmTokens(tokenEntries, batchResponse) {
  if (!tokenEntries.length || !batchResponse?.responses?.length) {
    return;
  }

  const staleTokenByUser = new Map();
  batchResponse.responses.forEach((response, index) => {
    if (!response.success && isStaleFcmError(response.error)) {
      const entry = tokenEntries[index];
      if (entry?.userId && entry?.token) {
        staleTokenByUser.set(entry.userId, entry.token);
      }
    }
  });

  if (staleTokenByUser.size === 0) {
    return;
  }

  const staleUserIds = Array.from(staleTokenByUser.keys());
  const staleUserSnaps = await Promise.all(
    staleUserIds.map((userId) => db.collection('users').doc(userId).get())
  );

  const batch = db.batch();
  let updates = 0;

  staleUserSnaps.forEach((userSnap, index) => {
    if (!userSnap.exists) {
      return;
    }

    const userId = staleUserIds[index];
    const staleToken = staleTokenByUser.get(userId);
    const data = userSnap.data() || {};
    const currentToken = data.deviceInfo?.fcmToken || data.fcmToken;

    // Avoid deleting if the token changed after this send operation started.
    if (!currentToken || currentToken !== staleToken) {
      return;
    }

    batch.update(userSnap.ref, {
      'deviceInfo.fcmToken': FieldValue.delete(),
      'deviceInfo.updatedAt': FieldValue.serverTimestamp(),
      fcmToken: FieldValue.delete(),
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
    });
    updates++;
  });

  if (updates > 0) {
    await batch.commit();
  }
}

async function sendGeofenceNotification(familyId, userId, userName, geofence, eventType) {
  const settings = geofence.settings || {};
  const geofenceName = geofence.name || 'a place';

  const recipientIds = await getNotifiableAdminIds(
    familyId,
    userId,
    settings.notifyMembers
  );

  if (recipientIds.length === 0) return;

  const titles = {
    entry: '📍 Arrival',
    exit: '🚶 Departure',
    dwell: '⏱️ Still there',
  };
  const actions = {
    entry: 'arrived at',
    exit: 'left',
    dwell: 'has been at',
  };
  const types = {
    entry: 'geofenceEntry',
    exit: 'geofenceExit',
    dwell: 'geofenceDwell',
  };

  const title = titles[eventType];
  const body = `${userName} ${actions[eventType]} ${geofenceName}`;

  await Promise.all([
    saveInAppNotifications(recipientIds, {
      type: types[eventType],
      title,
      body,
      data: {
        userId,
        familyId,
        geofenceName,
      },
    }),
    pushToUsers(recipientIds, {
      notification: { title, body },
      data: {
        type: types[eventType],
        userId,
        familyId,
        geofenceName,
      },
      android: { notification: { channelId: 'geofence_alerts' } },
    }),
  ]);
}
