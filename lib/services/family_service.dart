import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../data/models/location_model.dart';

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
  final _familyMembersController = StreamController<List<FamilyMemberData>>.broadcast();

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
      }
    } else {
      // Create user document if it doesn't exist
      await _createUserDocument(user);
    }
  }

  /// Create a new user document
  Future<void> _createUserDocument(User user) async {
    await _firestore.collection('users').doc(user.uid).set({
      'displayName': user.displayName ?? 'User',
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

    // Create family document
    final familyRef = await _firestore.collection('families').add({
      'name': familyName,
      'createdBy': user.uid,
      'createdByName': user.displayName ?? 'User',
      'createdAt': FieldValue.serverTimestamp(),
      'inviteCode': inviteCode,
      'inviteCodeExpiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'memberIds': [user.uid],
    });

    // Add current user as admin member
    await familyRef.collection('members').doc(user.uid).set({
      'userId': user.uid,
      'displayName': user.displayName ?? 'You',
      'photoUrl': user.photoURL,
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

    return familyRef.id;
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

    // Avoid downgrading roles or resetting metadata if the user already joined.
    final existingMember =
        await familyDoc.reference.collection('members').doc(user.uid).get();

    if (!existingMember.exists) {
      // Add user to family
      await familyDoc.reference.collection('members').doc(user.uid).set({
        'userId': user.uid,
        'displayName': user.displayName ?? 'User',
        'photoUrl': user.photoURL,
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
    if (_currentFamilyId == null) return;

    _familySubscription?.cancel();
    
    // Listen to family members from Firestore
    _familySubscription = _firestore
        .collection('families')
        .doc(_currentFamilyId)
        .collection('members')
        .snapshots()
        .listen((snapshot) async {
          final members = <FamilyMemberData>[];
          
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final memberId = doc.id;
            
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

            members.add(FamilyMemberData(
              id: memberId,
              displayName: data['displayName'] ?? 'Unknown',
              photoUrl: data['photoUrl'],
              role: data['role'] ?? 'member',
              isOnline: _isRecentlyActive(location?.timestamp),
              location: location,
              battery: location?.battery ?? 100,
              isCurrentUser: memberId == currentUserId,
            ));
          }

          _familyMembersController.add(members);
        });
  }

  /// Check if timestamp is recent (within 5 minutes)
  bool _isRecentlyActive(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp).inMinutes < 5;
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

      members.add(FamilyMemberData(
        id: memberId,
        displayName: data['displayName'] ?? 'Unknown',
        photoUrl: data['photoUrl'],
        role: data['role'] ?? 'member',
        isOnline: _isRecentlyActive(location?.timestamp),
        location: location,
        battery: location?.battery ?? 100,
        isCurrentUser: memberId == currentUserId,
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

    // Remove family from user's familyIds
    await _firestore.collection('users').doc(user.uid).update({
      'familyIds': FieldValue.arrayRemove([familyId]),
      'currentFamilyId': null,
    });

    // Remove user's location data
    await _database.ref('locations/$familyId/${user.uid}').remove();

    // Stop listening and clear current family
    _familySubscription?.cancel();
    _currentFamilyId = null;
  }

  /// Delete the current family (admin only)
  Future<void> deleteFamily() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    if (_currentFamilyId == null) throw Exception('No family selected');

    final familyId = _currentFamilyId!;

    // Check if user is admin
    final familyDoc = await _firestore.collection('families').doc(familyId).get();
    if (familyDoc.data()?['createdBy'] != user.uid) {
      throw Exception('Only the family admin can delete the family');
    }

    // Get all member IDs
    final memberIds = List<String>.from(familyDoc.data()?['memberIds'] ?? []);

    // Remove family from all members' familyIds
    for (final memberId in memberIds) {
      await _firestore.collection('users').doc(memberId).update({
        'familyIds': FieldValue.arrayRemove([familyId]),
        'currentFamilyId': null,
      });
    }

    // Delete all members subcollection
    final membersSnapshot = await _firestore
        .collection('families')
        .doc(familyId)
        .collection('members')
        .get();
    
    for (final doc in membersSnapshot.docs) {
      await doc.reference.delete();
    }

    // Delete location data for all members
    await _database.ref('locations/$familyId').remove();

    // Delete the family document
    await _firestore.collection('families').doc(familyId).delete();

    // Stop listening and clear current family
    _familySubscription?.cancel();
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
  
  /// Get family members stream by family ID (for external use)
  Stream<List<FamilyMemberData>> getFamilyMembersStream(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('members')
        .snapshots()
        .asyncMap((snapshot) async {
          final members = <FamilyMemberData>[];
          
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final memberId = doc.id;
            
            // Get real-time location from Realtime Database
            LocationModel? location;
            try {
              final locationSnapshot = await _database
                  .ref('locations/$familyId/$memberId')
                  .get();
              
              if (locationSnapshot.exists) {
                final locData = locationSnapshot.value as Map<dynamic, dynamic>;
                location = LocationModel.fromRealtimeDb(locData, memberId);
              }
            } catch (e) {
              // Location not available
            }

            members.add(FamilyMemberData(
              id: memberId,
              displayName: data['displayName'] ?? 'Unknown',
              photoUrl: data['photoUrl'],
              role: data['role'] ?? 'member',
              isOnline: _isRecentlyActive(location?.timestamp),
              location: location,
              battery: location?.battery ?? 100,
              isCurrentUser: memberId == currentUserId,
            ));
          }

          return members;
        });
  }

  /// Dispose
  void dispose() {
    _familySubscription?.cancel();
    _familyMembersController.close();
  }
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

  FamilyMemberData({
    required this.id,
    required this.displayName,
    this.photoUrl,
    required this.role,
    this.isOnline = false,
    this.location,
    this.battery = 100,
    this.isCurrentUser = false,
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
    if (!isOnline) return 'Offline';
    if (location?.address != null) return location!.address!;
    if (location != null) return 'Location available';
    return 'Online';
  }

  /// Check if member is moving
  bool get isMoving => (location?.speed ?? 0) > 1.0;

  /// Get speed in km/h
  double get speedKmh => (location?.speed ?? 0) * 3.6;

  /// Get time ago text
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
