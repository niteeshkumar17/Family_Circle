import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../data/models/location_model.dart';
import '../data/models/geofence_model.dart';
import '../services/background_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

/// Family Service
/// 
/// Handles family management, member tracking, and real-time location updates
class FamilyService {
  static final FamilyService _instance = FamilyService._internal();
  factory FamilyService() => _instance;
  FamilyService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _currentFamilyId;
  StreamSubscription? _familySubscription;
  StreamSubscription? _sosSubscription;
  StreamSubscription? _membersFeedSubscription;
  bool _isFirstFamilyLoad = true;
  final _familyMembersController = StreamController<List<FamilyMemberData>>.broadcast();
  final Map<String, _FamilyMembersFeed> _memberFeeds = {};

  /// Stream of family members with their locations
  Stream<List<FamilyMemberData>> get familyMembersStream => _familyMembersController.stream;

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Get current user's display name
  String? get currentUserName => _auth.currentUser?.displayName;

  /// Get current user's photo URL
  String? get currentUserPhoto => _auth.currentUser?.photoURL;

  /// Initialize the family service
  Future<void> initialize() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Check if user has a family
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    
    if (userDoc.exists) {
      final data = userDoc.data();
      _currentFamilyId = data?['currentFamilyId'];
      
      if (_currentFamilyId != null) {
        _startListeningToFamily();
        await _syncTrackingServices(_currentFamilyId!);
      }
    } else {
      // Create user document if it doesn't exist
      await _createUserDocument(user);
    }
  }

  /// Create a new user document
  Future<void> _createUserDocument(User user) async {
    final name = user.displayName ?? 'User';
    await _firestore.collection('users').doc(user.uid).set({
      'displayName': name,
      'name': name,
      'email': user.email,
      'photoUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'familyIds': [],
      'currentFamilyId': null,
    });
  }

  /// Create a new family
  Future<String> createFamily(String familyName) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final now = DateTime.now();
    String inviteCode;
    try {
      inviteCode = await _generateUniqueInviteCode();
    } catch (_) {
      throw Exception('Unable to create family right now. Please try again.');
    }

    // Fetch user profile from Firestore to get their real name (from 'name' or 'displayName')
    String resolvedName = 'User';
    String? resolvedPhotoUrl;
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        resolvedName = userDoc.data()?['displayName'] ?? userDoc.data()?['name'] ?? user.displayName ?? 'User';
        resolvedPhotoUrl = userDoc.data()?['photoUrl'] ?? user.photoURL;
      } else {
        resolvedName = user.displayName ?? 'User';
        resolvedPhotoUrl = user.photoURL;
      }
    } catch (e) {
      resolvedName = user.displayName ?? 'User';
      resolvedPhotoUrl = user.photoURL;
    }

    // Create family document
    final familyRef = await _firestore.collection('families').add({
      'name': familyName,
      'createdBy': user.uid,
      'createdByName': resolvedName,
      'createdAt': FieldValue.serverTimestamp(),
      'inviteCode': inviteCode,
      'inviteCodeExpiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'memberIds': [user.uid],
    });

    // Add current user as admin member
    await familyRef.collection('members').doc(user.uid).set({
      'userId': user.uid,
      'displayName': resolvedName,
      'photoUrl': resolvedPhotoUrl,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'locationSharingEnabled': true,
    });

    // Update user document
    await _firestore.collection('users').doc(user.uid).update({
      'familyIds': FieldValue.arrayUnion([familyRef.id]),
      'currentFamilyId': familyRef.id,
    });

    _currentFamilyId = familyRef.id;
    _startListeningToFamily();
    await _syncTrackingServices(familyRef.id);

    return familyRef.id;
  }

  /// Get all families the user belongs to
  Future<List<FamilyInfo>> getUserFamilies() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) return [];

    final familyIds = List<String>.from(userDoc.data()?['familyIds'] ?? []);
    if (familyIds.isEmpty) return [];

    final families = <FamilyInfo>[];
    for (final id in familyIds) {
      final doc = await _firestore.collection('families').doc(id).get();
      if (doc.exists) {
        final data = doc.data()!;
        families.add(FamilyInfo(
          id: doc.id,
          familyName: data['name'] ?? 'My Family',
          inviteCode: data['inviteCode'],
          memberCount: (data['memberIds'] as List?)?.length ?? 0,
          createdBy: data['createdBy'],
          createdByName: data['createdByName'],
        ));
      }
    }
    return families;
  }

  /// Every family the signed-in user belongs to.
  Future<List<String>> getUserFamilyIds() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    return List<String>.from(userDoc.data()?['familyIds'] ?? const []);
  }

  /// Point the tracking services at the active nest.
  ///
  /// Every path that changes which family is active funnels through here, so
  /// the background tracker can never keep publishing to the previous nest's
  /// key while the UI reads a different one.
  Future<void> _syncTrackingServices(String familyId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    var effectiveIds = <String>[familyId];
    try {
      final allFamilyIds = await getUserFamilyIds();
      if (allFamilyIds.isNotEmpty) effectiveIds = allFamilyIds;
    } catch (e) {
      debugPrint('Failed to read family list: $e');
    }

    await _publishMembershipIndex(user.uid, effectiveIds);

    try {
      await BackgroundLocationService().configureForUser(
        userId: user.uid,
        familyId: familyId,
        allFamilyIds: effectiveIds,
      );
    } catch (e) {
      debugPrint('Failed to configure background tracking: $e');
    }

    try {
      await LocationService().initialize(
        userId: user.uid,
        familyId: familyId,
      );
    } catch (e) {
      debugPrint('Failed to initialize foreground tracking: $e');
    }
  }

  /// Mirror membership into Realtime Database.
  ///
  /// The database rules scope reads of `locations`, `locationHistory` and
  /// `sos_active` to `family_members/{familyId}/{uid}`, and RTDB rules cannot
  /// query Firestore. A Cloud Function maintains this index for new members;
  /// writing it here as well keeps members who joined before that function
  /// existed from losing access.
  Future<void> _publishMembershipIndex(
    String userId,
    List<String> familyIds,
  ) async {
    for (final id in familyIds) {
      try {
        await _database.ref('family_members/$id/$userId').set(true);
      } catch (e) {
        debugPrint('Failed to index membership for $id: $e');
      }
    }
  }

  /// Switch the active family
  Future<void> switchFamily(String familyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore.collection('users').doc(user.uid).update({
      'currentFamilyId': familyId,
    });

    _currentFamilyId = familyId;
    _startListeningToFamily();
    await _syncTrackingServices(familyId);
  }

  /// Join a family with invite code
  Future<bool> joinFamily(String inviteCode) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Find family with invite code
    final familyQuery = await _firestore
        .collection('families')
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
        .limit(1)
        .get();

    if (familyQuery.docs.isEmpty) {
      return false;
    }

    final familyDoc = familyQuery.docs.first;
    final familyData = familyDoc.data();
    final familyId = familyDoc.id;
    
    // Check if invite code is expired
    final expiresAt = familyData['inviteCodeExpiresAt'] as Timestamp?;
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      throw Exception('Invite code has expired. Ask the family admin to generate a new code.');
    }

    // Fetch user profile from Firestore to get their real name (from 'name' or 'displayName')
    String resolvedName = 'User';
    String? resolvedPhotoUrl;
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        resolvedName = userDoc.data()?['displayName'] ?? userDoc.data()?['name'] ?? user.displayName ?? 'User';
        resolvedPhotoUrl = userDoc.data()?['photoUrl'] ?? user.photoURL;
      } else {
        resolvedName = user.displayName ?? 'User';
        resolvedPhotoUrl = user.photoURL;
      }
    } catch (e) {
      resolvedName = user.displayName ?? 'User';
      resolvedPhotoUrl = user.photoURL;
    }

    // Avoid downgrading roles or resetting metadata if the user already joined.
    final existingMember =
        await familyDoc.reference.collection('members').doc(user.uid).get();

    if (!existingMember.exists) {
      // Add user to family
      await familyDoc.reference.collection('members').doc(user.uid).set({
        'userId': user.uid,
        'displayName': resolvedName,
        'photoUrl': resolvedPhotoUrl,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
        'locationSharingEnabled': true,
      });

      // Update family memberIds
      await familyDoc.reference.update({
        'memberIds': FieldValue.arrayUnion([user.uid]),
      });
    }

    // Update user document
    await _firestore.collection('users').doc(user.uid).update({
      'familyIds': FieldValue.arrayUnion([familyId]),
      'currentFamilyId': familyId,
    });

    _currentFamilyId = familyId;
    _startListeningToFamily();
    await _syncTrackingServices(familyId);

    return true;
  }

  /// Generate a random invite code
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Generate an invite code that does not already exist.
  Future<String> _generateUniqueInviteCode() async {
    const maxAttempts = 5;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final code = _generateInviteCode();
      final existing = await _firestore
          .collection('families')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        return code;
      }
    }

    throw Exception('Failed to generate a unique invite code. Please try again.');
  }

  /// Start listening to family members
  void _startListeningToFamily() {
    final familyId = _currentFamilyId;
    if (familyId == null) return;

    _familySubscription?.cancel();
    _sosSubscription?.cancel();
    _membersFeedSubscription?.cancel();
    _isFirstFamilyLoad = true;

    // Roster changes drive join/removal notifications only; the member data
    // itself comes from the live feed below.
    _familySubscription = _firestore
        .collection('families')
        .doc(familyId)
        .collection('members')
        .snapshots()
        .listen((snapshot) async {
          if (_isFirstFamilyLoad) {
            _isFirstFamilyLoad = false;
            return;
          }

          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;

            if (change.type == DocumentChangeType.added &&
                data['userId'] != currentUserId) {
              final familyInfo = await getCurrentFamilyInfo();
              NotificationService().showMemberJoinedNotification(
                userName: data['displayName'] ?? 'A member',
                familyName: familyInfo?.familyName ?? 'the nest',
              );
            } else if (change.type == DocumentChangeType.removed &&
                data['userId'] == currentUserId) {
              final familyInfo = await getCurrentFamilyInfo();
              NotificationService().showRemovedFromFamilyNotification(
                familyName: familyInfo?.familyName ?? 'the nest',
              );
              _handleSelfRemovedFromFamily();
            }
          }
        });

    _membersFeedSubscription =
        getFamilyMembersStream(familyId).listen(_familyMembersController.add);

    // Listen for active SOS events for this family.
    //
    // The previous version filtered on `createdAt > Timestamp.now()`, captured
    // when the listener attached, so a server timestamp could never satisfy it
    // and no alert ever fired. Filter by recency instead and drop anything the
    // listener has already reported.
    final since = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 1)),
    );
    final announcedSosIds = <String>{};

    _sosSubscription = _firestore
        .collection('sos_events')
        .where('familyId', isEqualTo: familyId)
        .where('status', isEqualTo: 'active')
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;

            final data = change.doc.data();
            if (data == null || data['userId'] == currentUserId) continue;
            if (!announcedSosIds.add(change.doc.id)) continue;

            NotificationService().showSOSNotification(
              userName: data['userName'] ?? 'A member',
              eventId: change.doc.id,
              latitude: (data['triggerLocation']?['latitude'] as num?)
                      ?.toDouble() ??
                  0.0,
              longitude: (data['triggerLocation']?['longitude'] as num?)
                      ?.toDouble() ??
                  0.0,
            );
          }
        });
  }

  /// Handles when current user is removed from the family
  Future<void> _handleSelfRemovedFromFamily() async {
    final user = _auth.currentUser;
    if (user == null || _currentFamilyId == null) return;
    
    final familyId = _currentFamilyId!;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'familyIds': FieldValue.arrayRemove([familyId]),
        'currentFamilyId': null,
      });
      await _database.ref('locations/$familyId/${user.uid}').remove();
    } catch (_) {}

    _familySubscription?.cancel();
    _sosSubscription?.cancel();
    _currentFamilyId = null;
  }

  /// Check if timestamp is recent (within 2 minutes)
  bool _isRecentlyActive(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp).inMinutes.abs() < 2;
  }

  /// Get family members once
  Future<List<FamilyMemberData>> getFamilyMembers() async {
    if (_currentFamilyId == null) return [];

    final snapshot = await _firestore
        .collection('families')
        .doc(_currentFamilyId)
        .collection('members')
        .get();

    final members = <FamilyMemberData>[];
    
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final memberId = doc.id;
      final isCurrent = memberId == currentUserId;
      
      String memberName = data['displayName'] ?? 'Unknown';
      String? memberPhone = data['phone'] ?? data['phoneNumber'];
      
      // Fetch user profile from Firestore to get their real name (from 'name' or 'displayName')
      try {
        final userDoc = await _firestore.collection('users').doc(memberId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          final profileName = userData['displayName'] ?? userData['name'];
          final profilePhone = userData['phone'] ?? userData['phoneNumber'];
          
          if (profilePhone != null && profilePhone.toString().isNotEmpty) {
            memberPhone = profilePhone;
          }

          if (profileName != null) {
            memberName = profileName;
            
            // Self-healing: if this is the current user, ensure family member name matches profile name
            if (isCurrent && profileName != (data['displayName'] ?? '')) {
              doc.reference.update({'displayName': profileName}).catchError((_) {});
            }
          }
        }
      } catch (_) {}
      
      // Get real-time location from Realtime Database
      LocationModel? location;
      try {
        final locationSnapshot = await _database
            .ref('locations/$_currentFamilyId/$memberId')
            .get();
        
        if (locationSnapshot.exists) {
          final locData = locationSnapshot.value as Map<dynamic, dynamic>;
          location = LocationModel.fromRealtimeDb(locData, memberId);
        }
      } catch (e) {
        // Location not available
      }

      // Check presence node for online status
      bool memberOnline = false;
      try {
        final presenceSnapshot = await _database
            .ref('presence/$memberId')
            .get();
        if (presenceSnapshot.exists) {
          final presData = presenceSnapshot.value as Map<dynamic, dynamic>;
          final isPresenceOnline = presData['online'] == true;
          final lastSeenMs = presData['lastSeen'] as int?;
          if (isPresenceOnline && lastSeenMs != null) {
            final lastSeenTime = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
            memberOnline = DateTime.now().difference(lastSeenTime).inMinutes < 5;
          }
        }
      } catch (_) {}
      if (!memberOnline) {
        memberOnline = _isRecentlyActive(location?.timestamp);
      }

      members.add(FamilyMemberData(
        id: memberId,
        displayName: memberName,
        photoUrl: data['photoUrl'],
        role: data['role'] ?? 'member',
        isOnline: memberOnline,
        location: location,
        battery: location?.battery ?? 100,
        isCurrentUser: isCurrent,
        phone: memberPhone,
      ));
    }

    return members;
  }

  /// Listen to a specific member's location
  Stream<LocationModel?> listenToMemberLocation(String memberId) {
    if (_currentFamilyId == null) {
      return Stream.value(null);
    }

    return _database
        .ref('locations/$_currentFamilyId/$memberId')
        .onValue
        .map((event) {
          if (event.snapshot.value == null) return null;
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          return LocationModel.fromRealtimeDb(data, memberId);
        });
  }

  /// Get location history for a member on a specific date
  Future<List<Map<String, dynamic>>> getLocationHistory(String memberId, DateTime date) async {
    if (_currentFamilyId == null) return [];

    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    
    try {
      final snapshot = await _database
          .ref('locationHistory/$_currentFamilyId/$memberId/$dateKey')
          .get();

      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> history = [];

      data.forEach((key, value) {
        final pointData = value as Map<dynamic, dynamic>;
        history.add({
          'latitude': pointData['latitude'],
          'longitude': pointData['longitude'],
          'accuracy': pointData['accuracy'],
          'speed': pointData['speed'],
          'address': pointData['address'],
          'battery': pointData['battery'],
          'isCharging': pointData['isCharging'],
          'timestamp': pointData['timestamp'] ?? int.parse(key.toString()),
        });
      });

      // Sort chronologically
      history.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

      return history;
    } catch (e) {
      debugPrint('Error fetching location history: $e');
      return [];
    }
  }

  /// Update current user's location
  Future<void> updateMyLocation(LocationModel location) async {
    final userId = currentUserId;
    if (userId == null || _currentFamilyId == null) return;

    await _database
        .ref('locations/$_currentFamilyId/$userId')
        .set(location.toRealtimeDb());
  }

  /// Get current family info
  Future<FamilyInfo?> getCurrentFamilyInfo() async {
    if (_currentFamilyId == null) return null;

    final doc = await _firestore
        .collection('families')
        .doc(_currentFamilyId)
        .get();

    if (!doc.exists) return null;

    final data = doc.data()!;
    final createdAt = data['createdAt'] as Timestamp?;
    final expiresAt = data['inviteCodeExpiresAt'] as Timestamp?;
    
    return FamilyInfo(
      id: doc.id,
      familyName: data['name'] ?? 'My Family',
      inviteCode: data['inviteCode'],
      memberCount: (data['memberIds'] as List?)?.length ?? 0,
      createdBy: data['createdBy'],
      createdByName: data['createdByName'],
      createdAt: createdAt?.toDate(),
      inviteCodeExpiresAt: expiresAt?.toDate(),
    );
  }

  /// Get invite code for current family (auto-regenerates if expired)
  Future<String?> getInviteCode() async {
    if (_currentFamilyId == null) return null;

    final doc = await _firestore
        .collection('families')
        .doc(_currentFamilyId)
        .get();

    final data = doc.data();
    if (data == null) return null;
    
    final expiresAt = data['inviteCodeExpiresAt'] as Timestamp?;
    final currentCode = data['inviteCode'] as String?;
    
    // Check if code is expired or doesn't exist
    if (currentCode == null || expiresAt == null || expiresAt.toDate().isBefore(DateTime.now())) {
      // Regenerate the code
      return await regenerateInviteCode();
    }
    
    return currentCode;
  }
  
  /// Regenerate invite code (generates new code valid for 24 hours)
  Future<String> regenerateInviteCode() async {
    if (_currentFamilyId == null) throw Exception('No family selected');
    
    final newCode = await _generateUniqueInviteCode();
    final expiresAt = DateTime.now().add(const Duration(hours: 24));
    
    await _firestore.collection('families').doc(_currentFamilyId).update({
      'inviteCode': newCode,
      'inviteCodeExpiresAt': Timestamp.fromDate(expiresAt),
    });
    
    return newCode;
  }

  /// Update family name
  Future<void> updateFamilyName(String newName) async {
    if (_currentFamilyId == null) throw Exception('No family selected');
    
    await _firestore.collection('families').doc(_currentFamilyId).update({
      'name': newName,
    });
  }

  /// Leave the current family
  Future<void> leaveFamily() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    if (_currentFamilyId == null) throw Exception('No family selected');

    final familyId = _currentFamilyId!;

    try {
      // Remove user from family members
      await _firestore
          .collection('families')
          .doc(familyId)
          .collection('members')
          .doc(user.uid)
          .delete();

      // Remove user from family memberIds
      await _firestore.collection('families').doc(familyId).update({
        'memberIds': FieldValue.arrayRemove([user.uid]),
      });
    } on FirebaseException catch (e) {
      // If we get permission-denied or not-found, it usually means we were 
      // already removed by an admin. We gracefully catch this and proceed to 
      // clean up our local state.
      if (e.code != 'permission-denied' && e.code != 'not-found') {
        rethrow;
      }
    }

    final remaining = (await getUserFamilyIds())
        .where((id) => id != familyId)
        .toList();
    final nextFamilyId = remaining.isEmpty ? null : remaining.first;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'familyIds': FieldValue.arrayRemove([familyId]),
        'currentFamilyId': nextFamilyId,
      });

      await _database.ref('locations/$familyId/${user.uid}').remove();
      await _database.ref('locationHistory/$familyId/${user.uid}').remove();
      await _database.ref('family_members/$familyId/${user.uid}').remove();
    } catch (e) {
      debugPrint('Best-effort cleanup after leaving $familyId failed: $e');
    }

    _familySubscription?.cancel();
    _sosSubscription?.cancel();
    _currentFamilyId = nextFamilyId;

    // Leaving the last nest has to stop the tracker, otherwise it keeps
    // publishing to a nest the user is no longer part of.
    if (nextFamilyId == null) {
      await BackgroundLocationService().clearUser();
      await BackgroundLocationService().stop();
      await LocationService().reset();
    } else {
      _startListeningToFamily();
      await _syncTrackingServices(nextFamilyId);
    }
  }

  /// Remove a member from the family (admin only)
  ///
  /// Only the membership document is deleted here. Detaching the family from
  /// the other user's profile and wiping their Realtime Database location is
  /// done by the `onMemberRemoved` Cloud Function, because the security rules
  /// deliberately stop one user from writing another user's data.
  Future<void> removeMemberFromFamily(String familyId, String memberId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    if (memberId == user.uid) {
      throw Exception('Use "Leave nest" to remove yourself');
    }

    if (!await _isFamilyAdmin(familyId, user.uid)) {
      throw Exception('Only a nest admin can remove members');
    }

    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('members')
        .doc(memberId)
        .delete();

    await _firestore.collection('families').doc(familyId).update({
      'memberIds': FieldValue.arrayRemove([memberId]),
    });
  }

  /// True when [userId] created the family or holds the admin role.
  Future<bool> _isFamilyAdmin(String familyId, String userId) async {
    final familyDoc = await _firestore.collection('families').doc(familyId).get();
    if (familyDoc.data()?['createdBy'] == userId) return true;

    final memberDoc = await _firestore
        .collection('families')
        .doc(familyId)
        .collection('members')
        .doc(userId)
        .get();
    return memberDoc.data()?['role'] == 'admin';
  }

  /// Delete the current family (admin only)
  Future<void> deleteFamily() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    if (_currentFamilyId == null) throw Exception('No family selected');

    final familyId = _currentFamilyId!;

    try {
      // Check if user is admin
      final familyDoc = await _firestore.collection('families').doc(familyId).get();
      if (familyDoc.exists) {
        if (familyDoc.data()?['createdBy'] != user.uid) {
          throw Exception('Only the family admin can delete the family');
        }

        // Detaching every other member's profile and clearing the Realtime
        // Database subtree is the `onFamilyDeleted` Cloud Function's job; the
        // rules stop a client from touching another user's documents.
        final membersSnapshot = await _firestore
            .collection('families')
            .doc(familyId)
            .collection('members')
            .get();
        for (final doc in membersSnapshot.docs) {
          await doc.reference.delete();
        }

        await _firestore.collection('families').doc(familyId).delete();
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'not-found') {
        rethrow;
      }
    }

    try {
      // Fallback: Ensure current user removes this from their own doc if something failed
      await _firestore.collection('users').doc(user.uid).update({
        'familyIds': FieldValue.arrayRemove([familyId]),
        'currentFamilyId': null,
      });
    } catch (_) {}

    // Stop listening and clear current family
    _familySubscription?.cancel();
    _sosSubscription?.cancel();
    _currentFamilyId = null;
  }
  
  /// Get invite code expiry time
  Future<DateTime?> getInviteCodeExpiry() async {
    if (_currentFamilyId == null) return null;

    final doc = await _firestore
        .collection('families')
        .doc(_currentFamilyId)
        .get();

    final expiresAt = doc.data()?['inviteCodeExpiresAt'] as Timestamp?;
    return expiresAt?.toDate();
  }

  /// Check if user has a family
  bool get hasFamily => _currentFamilyId != null;

  /// Get current family ID
  String? get currentFamilyId => _currentFamilyId;
  
  /// Get current user's family ID (async method for compatibility)
  Future<String?> getCurrentUserFamilyId() async {
    if (_currentFamilyId != null) return _currentFamilyId;
    
    // Try to fetch from Firestore if not cached
    final user = _auth.currentUser;
    if (user == null) return null;
    
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      _currentFamilyId = userDoc.data()?['currentFamilyId'];
    }
    return _currentFamilyId;
  }
  
  /// Get family info by ID
  Future<FamilyInfo?> getFamilyInfo(String familyId) async {
    final doc = await _firestore
        .collection('families')
        .doc(familyId)
        .get();

    if (!doc.exists) return null;

    final data = doc.data()!;
    return FamilyInfo(
      id: doc.id,
      familyName: data['name'] ?? 'My Family',
      inviteCode: data['inviteCode'],
      memberCount: (data['memberIds'] as List?)?.length ?? 0,
    );
  }
  
  /// Live stream of a family's members, including their current positions.
  ///
  /// Merges the Firestore roster with the Realtime Database `locations/` and
  /// `presence/` nodes, so a member moving emits a new list immediately.
  /// Previously this only listened to Firestore and read locations once per
  /// roster change, which left map markers frozen until the app restarted.
  Stream<List<FamilyMemberData>> getFamilyMembersStream(String familyId) {
    final existing = _memberFeeds[familyId];
    if (existing != null) return existing.stream;

    final feed = _FamilyMembersFeed(
      familyId: familyId,
      service: this,
      onDisposed: () => _memberFeeds.remove(familyId),
    );
    _memberFeeds[familyId] = feed;
    return feed.stream;
  }

  // ==========================================
  // Geofence Methods
  // ==========================================

  /// Stream of geofences for a given family
  Stream<List<GeofenceModel>> getGeofencesStream(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('geofences')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => GeofenceModel.fromFirestore(doc)).toList();
    });
  }

  /// Add a new geofence
  Future<void> addGeofence(GeofenceModel geofence) async {
    await _firestore
        .collection('families')
        .doc(geofence.familyId)
        .collection('geofences')
        .doc(geofence.id)
        .set(geofence.toJson());
  }

  /// Update an existing geofence
  Future<void> updateGeofence(GeofenceModel geofence) async {
    await _firestore
        .collection('families')
        .doc(geofence.familyId)
        .collection('geofences')
        .doc(geofence.id)
        .update(geofence.toJson());
  }

  /// Delete a geofence
  Future<void> deleteGeofence(String familyId, String geofenceId) async {
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('geofences')
        .doc(geofenceId)
        .delete();
  }

  /// Tear down all listeners for the signed-in user.
  ///
  /// Called on sign-out so a new session does not inherit the previous user's
  /// family listeners.
  Future<void> reset() async {
    await _familySubscription?.cancel();
    await _sosSubscription?.cancel();
    await _membersFeedSubscription?.cancel();
    _familySubscription = null;
    _sosSubscription = null;
    _membersFeedSubscription = null;

    for (final feed in _memberFeeds.values.toList()) {
      await feed.close();
    }
    _memberFeeds.clear();

    _currentFamilyId = null;
    _isFirstFamilyLoad = true;
  }

  /// Dispose
  Future<void> dispose() async {
    await reset();
    if (!_familyMembersController.isClosed) {
      await _familyMembersController.close();
    }
  }
}

/// Live view of one family's members.
///
/// Keeps three Realtime Database / Firestore sources in sync and emits a fresh
/// list whenever any of them changes:
///  * Firestore `families/{id}/members` — the roster, roles and photos
///  * Realtime Database `locations/{familyId}` — every member's position
///  * Realtime Database `presence/{uid}` — online state while stationary
///
/// User profiles are cached per member so a position update does not trigger a
/// Firestore read for every member in the nest.
class _FamilyMembersFeed {
  _FamilyMembersFeed({
    required this.familyId,
    required this.service,
    required this.onDisposed,
  }) {
    _controller = StreamController<List<FamilyMemberData>>.broadcast(
      onListen: _start,
      onCancel: _stopWhenIdle,
    );
  }

  final String familyId;
  final FamilyService service;
  final VoidCallback onDisposed;

  late final StreamController<List<FamilyMemberData>> _controller;
  StreamSubscription? _rosterSub;
  StreamSubscription? _locationsSub;
  final Map<String, StreamSubscription> _presenceSubs = {};

  final Map<String, Map<String, dynamic>> _roster = {};
  final Map<String, LocationModel> _locations = {};
  final Map<String, bool> _presenceOnline = {};
  final Map<String, _MemberProfile> _profiles = {};

  bool _started = false;
  List<FamilyMemberData> _latest = const [];

  Stream<List<FamilyMemberData>> get stream => _controller.stream;

  void _start() {
    if (_started) return;
    _started = true;

    _rosterSub = service._firestore
        .collection('families')
        .doc(familyId)
        .collection('members')
        .snapshots()
        .listen((snapshot) async {
      _roster
        ..clear()
        ..addEntries(snapshot.docs.map((d) => MapEntry(d.id, d.data())));

      _syncPresenceSubscriptions();
      await _refreshProfiles(snapshot.docs);
      _emit();
    }, onError: (Object e) => debugPrint('Family roster stream error: $e'));

    _locationsSub =
        service._database.ref('locations/$familyId').onValue.listen((event) {
      _locations.clear();
      final value = event.snapshot.value;
      if (value is Map) {
        value.forEach((key, raw) {
          if (raw is! Map) return;
          final parsed =
              LocationModel.tryFromRealtimeDb(raw, key.toString());
          if (parsed != null) _locations[key.toString()] = parsed;
        });
      }
      _emit();
    }, onError: (Object e) => debugPrint('Family locations stream error: $e'));
  }

  void _syncPresenceSubscriptions() {
    for (final memberId in _roster.keys) {
      if (_presenceSubs.containsKey(memberId)) continue;
      _presenceSubs[memberId] =
          service._database.ref('presence/$memberId').onValue.listen((event) {
        final value = event.snapshot.value;
        var online = false;
        if (value is Map && value['online'] == true) {
          final lastSeenMs = (value['lastSeen'] as num?)?.toInt();
          if (lastSeenMs != null) {
            final lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
            // The tracker heartbeats once a minute; allow a few missed beats
            // before calling someone offline.
            online = DateTime.now().difference(lastSeen).inMinutes < 5;
          }
        }
        _presenceOnline[memberId] = online;
        _emit();
      }, onError: (Object e) => debugPrint('Presence stream error: $e'));
    }

    for (final memberId in _presenceSubs.keys.toList()) {
      if (_roster.containsKey(memberId)) continue;
      _presenceSubs.remove(memberId)?.cancel();
      _presenceOnline.remove(memberId);
      _profiles.remove(memberId);
    }
  }

  Future<void> _refreshProfiles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      if (_profiles.containsKey(doc.id)) continue;
      try {
        final userDoc =
            await service._firestore.collection('users').doc(doc.id).get();
        if (!userDoc.exists) continue;

        final userData = userDoc.data()!;
        final name = userData['displayName'] ?? userData['name'];
        final phone = userData['phone'] ?? userData['phoneNumber'];
        _profiles[doc.id] = _MemberProfile(
          displayName: name?.toString(),
          phone: phone?.toString(),
          photoUrl: userData['photoUrl']?.toString(),
        );

        // Self-healing: keep the roster entry in step with the profile name.
        if (doc.id == service.currentUserId &&
            name != null &&
            name != (doc.data()['displayName'] ?? '')) {
          doc.reference.update({'displayName': name}).catchError((_) {});
        }
      } catch (_) {
        // Profile is optional; the roster entry still renders.
      }
    }
  }

  void _emit() {
    if (_controller.isClosed) return;

    final members = <FamilyMemberData>[];
    for (final entry in _roster.entries) {
      final memberId = entry.key;
      final data = entry.value;
      final profile = _profiles[memberId];
      final location = _locations[memberId];

      final online = _presenceOnline[memberId] == true ||
          service._isRecentlyActive(location?.timestamp);

      members.add(FamilyMemberData(
        id: memberId,
        displayName: profile?.displayName ??
            data['displayName']?.toString() ??
            'Unknown',
        photoUrl: data['photoUrl']?.toString() ?? profile?.photoUrl,
        role: data['role']?.toString() ?? 'member',
        isOnline: online,
        location: location,
        // Only claim a battery level when a real reading exists, otherwise the
        // UI shows a confident "100%" for members who never reported.
        battery: location?.battery ?? 0,
        isCurrentUser: memberId == service.currentUserId,
        phone: profile?.phone ?? data['phone']?.toString() ??
            data['phoneNumber']?.toString(),
      ));
    }

    members.sort((a, b) {
      if (a.isCurrentUser != b.isCurrentUser) return a.isCurrentUser ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    _latest = members;
    _controller.add(_latest);
  }

  void _stopWhenIdle() {
    if (_controller.hasListener) return;
    close();
  }

  Future<void> close() async {
    await _rosterSub?.cancel();
    await _locationsSub?.cancel();
    for (final sub in _presenceSubs.values) {
      await sub.cancel();
    }
    _presenceSubs.clear();
    _started = false;
    onDisposed();
    if (!_controller.isClosed) await _controller.close();
  }
}

class _MemberProfile {
  final String? displayName;
  final String? phone;
  final String? photoUrl;

  const _MemberProfile({this.displayName, this.phone, this.photoUrl});
}

/// Family member data with location
class FamilyMemberData {
  final String id;
  final String displayName;
  final String? photoUrl;
  final String role;
  final bool isOnline;
  final LocationModel? location;
  final int battery;
  final bool isCurrentUser;
  final String? phone;

  FamilyMemberData({
    required this.id,
    required this.displayName,
    this.photoUrl,
    required this.role,
    this.isOnline = false,
    this.location,
    this.battery = 100,
    this.isCurrentUser = false,
    this.phone,
  });

  /// Alias for displayName for convenience
  String get name => displayName;
  
  /// Get latitude from location
  double? get latitude => location?.latitude;
  
  /// Get longitude from location
  double? get longitude => location?.longitude;
  
  /// Get battery level
  int get batteryLevel => battery;
  
  /// Get last seen time
  DateTime? get lastSeen => location?.timestamp;

  /// Get status text based on location
  String get statusText {
    if (location?.address != null) return location!.address!;
    if (!isOnline) return 'Offline';
    if (location != null) return 'Location available';
    return 'Online';
  }

  /// Check if member is moving
  bool get isMoving => (location?.speed ?? 0) > 1.0;

  /// Get speed in km/h
  double get speedKmh => (location?.speed ?? 0) * 3.6;

  /// Get time ago text — shows when location was last updated (not online status)
  String get lastSeenText {
    if (location?.timestamp == null) return 'Never';
    
    final diff = DateTime.now().difference(location!.timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Family info
class FamilyInfo {
  final String id;
  final String familyName;
  final String? inviteCode;
  final int memberCount;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? inviteCodeExpiresAt;

  FamilyInfo({
    required this.id,
    required this.familyName,
    this.inviteCode,
    this.memberCount = 0,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.inviteCodeExpiresAt,
  });
  
  /// Alias for familyName
  String get name => familyName;
  
  /// Check if invite code is expired
  bool get isInviteCodeExpired {
    if (inviteCodeExpiresAt == null) return true;
    return inviteCodeExpiresAt!.isBefore(DateTime.now());
  }
}
