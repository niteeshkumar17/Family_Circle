import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:location/location.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import '../config/app_config.dart';
import '../firebase_options.dart';
import 'location_cache_service.dart';
import 'dart:math' as math;

/// Background Location Service
/// 
/// This service runs in the background to track user location and sync
/// with Firebase Realtime Database. It uses adaptive intervals based on
/// movement to optimize battery usage.
class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isInitialized = false;

  /// Initialize the background service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true, // Auto-start when app launches
        isForegroundMode: true, // Required for Android 10+
        notificationChannelId: 'family_nest_location',
        initialNotificationTitle: 'FamilyNest',
        initialNotificationContent: 'Location sharing is active',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: true, // Restart after device reboot
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isInitialized = true;
  }

  /// Start the background service
  Future<void> start() async {
    if (!_isInitialized) {
      await initialize();
    }
    await _service.startService();
  }

  /// Stop the background service
  Future<void> stop() async {
    _service.invoke('stopService');
  }

  /// Check if service is running
  Future<bool> isRunning() async {
    return await _service.isRunning();
  }

  /// Update user ID for location tracking (persists + notifies service)
  Future<void> setUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    _service.invoke('setUserId', {'userId': userId});
  }

  /// Set family ID for location tracking (persists + notifies service)
  Future<void> setFamilyId(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('familyId', familyId);
    _service.invoke('setFamilyId', {'familyId': familyId});
  }

  /// Configure background service with user and family IDs.
  /// Call this after login and whenever the active family changes.
  Future<void> configureForUser({
    required String userId,
    required String familyId,
  }) async {
    await setUserId(userId);
    await setFamilyId(familyId);
  }

  /// Clear user data (call on sign-out)
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('familyId');
    _service.invoke('setUserId', {'userId': ''});
    _service.invoke('setFamilyId', {'familyId': ''});
  }

  /// Enable/disable location sharing
  void setLocationSharingEnabled(bool enabled) {
    _service.invoke('setLocationSharing', {'enabled': enabled});
  }

  /// Set tracking interval
  void setTrackingInterval(int seconds) {
    _service.invoke('setInterval', {'seconds': seconds});
  }

  /// Enable SOS mode (high frequency tracking)
  void enableSOSMode() {
    _service.invoke('enableSOSMode');
  }

  /// Disable SOS mode
  void disableSOSMode() {
    _service.invoke('disableSOSMode');
  }
}

/// Main background service entry point
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // Ensure Flutter is initialized
  DartPluginRegistrant.ensureInitialized();

  // Initialize Firebase in background isolate
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // State variables
  String? userId;
  String? familyId;
  bool locationSharingEnabled = true;
  int trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
  bool sosMode = false;
  LocationData? lastPosition;
  DateTime? lastUpdateTime;
  String? presenceRegisteredUserId;
  int consecutiveGpsFailures = 0;

  // Services
  final battery = Battery();
  final connectivity = Connectivity();
  final database = FirebaseDatabase.instance;
  final prefs = await SharedPreferences.getInstance();
  final location = Location();

  // ─── Helper: ensure userId/familyId are loaded ───
  Future<void> reloadIdentityFromPrefs() async {
    await prefs.reload();
    userId ??= prefs.getString('userId');
    familyId ??= prefs.getString('familyId');
    locationSharingEnabled = prefs.getBool('locationSharingEnabled') ?? true;
  }

  // ─── Helper: build location payload ───
  Future<Map<String, dynamic>> buildLocationPayload({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
  }) async {
    int batteryLevel = 100;
    bool isCharging = false;
    try {
      batteryLevel = await battery.batteryLevel;
      final batteryState = await battery.batteryState;
      isCharging = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;
    } catch (_) {}

    String networkStatus = 'unknown';
    try {
      final connectivityResult = await connectivity.checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        networkStatus = 'wifi';
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        networkStatus = 'mobile';
      } else {
        networkStatus = 'offline';
      }
    } catch (_) {}

    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'battery': batteryLevel,
      'isCharging': isCharging,
      'networkStatus': networkStatus,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isActive': true,
    };
  }

  // ─── Helper: push location to Firebase (with offline cache fallback) ───
  Future<bool> pushLocationToFirebase(Map<String, dynamic> locationData) async {
    if (userId == null || familyId == null) return false;

    try {
      await database
          .ref('locations/$familyId/$userId')
          .set(locationData);
      return true;
    } catch (pushError) {
      // Cache for later if Firebase push fails
      try {
        await LocationCacheService().cacheLocation(
          userId: userId!,
          familyId: familyId!,
          locationData: locationData,
        );
      } catch (_) {}
      return false;
    }
  }

  // ─── Helper: try to get GPS position with fallback ───
  Future<LocationData?> getLocationSafe() async {
    try {
      // Try high-accuracy first with generous timeout
      return await location.getLocation().timeout(
        const Duration(seconds: 30),
      );
    } catch (_) {}

    // Fallback: try low-accuracy (uses network/cell instead of GPS)
    try {
      await location.changeSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 0,
        interval: 1000,
      );
      final result = await location.getLocation().timeout(
        const Duration(seconds: 15),
      );
      // Restore high-accuracy for stream
      await location.changeSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        interval: 15000,
      );
      return result;
    } catch (_) {
      // Restore settings even on failure
      try {
        await location.changeSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          interval: 15000,
        );
      } catch (_) {}
    }

    return null; // All attempts failed
  }

  Future<void> configurePresenceOnDisconnect(String uid) async {
    if (presenceRegisteredUserId != null && presenceRegisteredUserId != uid) {
      try {
        await database.ref('presence/$presenceRegisteredUserId').onDisconnect().cancel();
      } catch (_) {}
    }

    try {
      final presenceRef = database.ref('presence/$uid');
      await presenceRef.onDisconnect().update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
        'appState': 'offline',
      });
      presenceRegisteredUserId = uid;
    } catch (_) {}
  }

  // Load saved state
  userId = prefs.getString('userId');
  familyId = prefs.getString('familyId');
  locationSharingEnabled = prefs.getBool('locationSharingEnabled') ?? true;

  if (userId != null && userId!.isNotEmpty) {
    await configurePresenceOnDisconnect(userId!);
  }

  // Configure location settings in the isolate
  // KEY FIX: distanceFilter = 0 so the stream fires even when the user is stationary.
  // The adaptive interval logic in the stream listener handles throttling instead.
  try {
    await location.changeSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,   // ← was 10, caused zero events when stationary
      interval: 15000,
    );
    await location.enableBackgroundMode(enable: true);
  } catch (e) {
    if (kDebugMode) {
      print('Could not configure location in isolate: $e');
    }
  }

  // Battery optimizer
  final batteryOptimizer = BatteryOptimizedTracker();

  // Setup reactive location stream subscription
  StreamSubscription<LocationData>? locationSubscription;

  void startLocationListening() {
    locationSubscription?.cancel();
    locationSubscription = location.onLocationChanged.listen((position) async {
      final now = DateTime.now();

      // Skip if location sharing is disabled
      if (!locationSharingEnabled || userId == null || familyId == null) {
        return;
      }

      // Check if we should update based on tracking interval
      if (lastUpdateTime != null) {
        final elapsed = now.difference(lastUpdateTime!).inSeconds;
        if (elapsed < trackingIntervalSeconds) {
          return; // Not time yet (respect adaptive interval)
        }
      }

      // Calculate optimal adaptive interval
      if (!sosMode) {
        trackingIntervalSeconds = batteryOptimizer.calculateOptimalInterval(
          position.speed ?? 0,
        );
      }

      try {
        final locationData = await buildLocationPayload(
          latitude: position.latitude ?? lastPosition?.latitude ?? 0,
          longitude: position.longitude ?? lastPosition?.longitude ?? 0,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speed: position.speed,
          heading: position.heading,
        );

        // Update Firebase Realtime Database
        final succeeded = await pushLocationToFirebase(locationData);

        // Update local state
        lastPosition = position;
        lastUpdateTime = now;
        consecutiveGpsFailures = 0;

        // Update notification info
        if (service is AndroidServiceInstance) {
          final pendingCount = succeeded
              ? 0
              : await LocationCacheService().getPendingCount();
          final cacheInfo = pendingCount > 0 ? ' ($pendingCount cached)' : '';
          service.setForegroundNotificationInfo(
            title: 'FamilyNest',
            content: sosMode
                ? '🚨 SOS Mode - Tracking active'
                : '📍 Location sharing active$cacheInfo',
          );
        }

        // Invoke location update event to main app
        service.invoke('locationUpdate', locationData);
      } catch (e) {
        if (kDebugMode) {
          print('Location update failed in background stream: $e');
        }
      }
    });
  }

  // Start listening to the stream
  startLocationListening();

  // Handle service commands
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) async {
    locationSubscription?.cancel();
    if (userId != null && userId!.isNotEmpty) {
      await database.ref('presence/$userId').set({
        'online': false,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'appState': 'stopped',
      });
      await database.ref('presence/$userId').onDisconnect().cancel();
      presenceRegisteredUserId = null;
    }
    service.stopSelf();
  });

  service.on('setUserId').listen((event) async {
    userId = event?['userId'];
    if (userId == null || userId!.isEmpty) {
      final previousUserId = presenceRegisteredUserId;
      if (previousUserId != null) {
        await database.ref('presence/$previousUserId').set({
          'online': false,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'appState': 'signed_out',
        });
        await database.ref('presence/$previousUserId').onDisconnect().cancel();
        presenceRegisteredUserId = null;
      }
      await prefs.remove('userId');
    } else {
      await prefs.setString('userId', userId!);
      await configurePresenceOnDisconnect(userId!);
    }
  });

  service.on('setFamilyId').listen((event) async {
    familyId = event?['familyId'];
    if (familyId == null || familyId!.isEmpty) {
      await prefs.remove('familyId');
    } else {
      await prefs.setString('familyId', familyId!);
    }
  });

  service.on('setLocationSharing').listen((event) async {
    locationSharingEnabled = event?['enabled'] ?? true;
    await prefs.setBool('locationSharingEnabled', locationSharingEnabled);
  });

  service.on('setInterval').listen((event) {
    trackingIntervalSeconds = event?['seconds'] ?? AppConfig.locationUpdateIntervalSeconds;
  });

  service.on('enableSOSMode').listen((event) {
    sosMode = true;
    trackingIntervalSeconds = AppConfig.sosTrackingIntervalSeconds;
  });

  service.on('disableSOSMode').listen((event) {
    sosMode = false;
    trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
  });

  // ════════════════════════════════════════════════════════════════════════
  // KEEP-ALIVE TIMER — runs every 60 seconds
  //
  // This is the CRITICAL heartbeat that guarantees location + presence
  // updates even when the GPS stream is silent (e.g. stationary, indoors,
  // doze mode throttling the stream).
  //
  // KEY DESIGN DECISION: Even if GPS fails, we STILL push the last-known
  // position with a fresh timestamp. This keeps the user showing as
  // "online" in the family list, which is the #1 user expectation.
  // ════════════════════════════════════════════════════════════════════════
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    // Reload identity from prefs in case the main isolate wrote them
    // after this isolate started (race condition fix)
    await reloadIdentityFromPrefs();

    if (userId == null || userId!.isEmpty) return;

    final now = DateTime.now();

    // 1. ── Presence heartbeat (always runs, independent of GPS) ──
    try {
      await database.ref('presence/$userId').set({
        'online': true,
        'lastSeen': now.millisecondsSinceEpoch,
        'appState': 'background',
      });
      await configurePresenceOnDisconnect(userId!);
    } catch (e) {
      if (kDebugMode) {
        print('Presence update failed: $e');
      }
    }

    // 2. ── Keep-alive location push ──
    if (!locationSharingEnabled || familyId == null) return;

    // Try to get a fresh GPS fix
    final position = await getLocationSafe();

    if (position != null &&
        position.latitude != null &&
        position.longitude != null) {
      // ✅ GPS succeeded — push fresh coordinates
      consecutiveGpsFailures = 0;

      final locationData = await buildLocationPayload(
        latitude: position.latitude!,
        longitude: position.longitude!,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
      );

      await pushLocationToFirebase(locationData);
      lastPosition = position;
      lastUpdateTime = now;

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'FamilyNest',
          content: sosMode
              ? '🚨 SOS Mode - Tracking active'
              : '📍 Location updated ${_formatTime(now)}',
        );
      }

      service.invoke('locationUpdate', locationData);
    } else {
      // ❌ GPS failed — but we STILL push last-known coords with a fresh
      //    timestamp so the user doesn't go "offline".
      consecutiveGpsFailures++;

      if (lastPosition != null &&
          lastPosition!.latitude != null &&
          lastPosition!.longitude != null) {
        final locationData = await buildLocationPayload(
          latitude: lastPosition!.latitude!,
          longitude: lastPosition!.longitude!,
          accuracy: lastPosition!.accuracy,
          altitude: lastPosition!.altitude,
          speed: 0,
          heading: lastPosition!.heading,
        );

        await pushLocationToFirebase(locationData);
        lastUpdateTime = now;

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'FamilyNest',
            content: '📍 Location active (GPS recovering...)',
          );
        }

        service.invoke('locationUpdate', locationData);
      }

      // If GPS has been failing for too long, restart the stream listener
      if (consecutiveGpsFailures >= 3) {
        if (kDebugMode) {
          print('GPS failed $consecutiveGpsFailures times, restarting stream...');
        }
        startLocationListening();
        consecutiveGpsFailures = 0;
      }
    }
  });

  // Connectivity listener — batch upload cached locations when back online
  connectivity.onConnectivityChanged.listen((result) async {
    final isOnline = result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.mobile);

    if (!isOnline || userId == null || familyId == null) return;

    try {
      final cache = LocationCacheService();
      final pendingCount = await cache.getPendingCount();
      if (pendingCount == 0) return;

      if (kDebugMode) {
        print('Back online — uploading $pendingCount cached locations...');
      }

      // Upload in batches
      while (true) {
        final batch = await cache.getPendingLocations();
        if (batch.isEmpty) break;

        final syncedIds = <int>[];
        for (final row in batch) {
          try {
            final data = cache.rowToLocationData(row);
            await database
                .ref('locations/${row['family_id']}/${row['user_id']}')
                .set(data);
            syncedIds.add(row['id'] as int);
          } catch (e) {
            // Stop batch on first failure (still offline?)
            break;
          }
        }

        if (syncedIds.isNotEmpty) {
          await cache.markAsSynced(syncedIds);
        }

        // If we couldn't sync any, connection is still bad
        if (syncedIds.length < batch.length) break;
      }

      if (kDebugMode) {
        final remaining = await cache.getPendingCount();
        print('Cache upload complete. Remaining: $remaining');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Cache upload failed: $e');
      }
    }
  });
}

/// Format a DateTime for the notification (e.g. "7:23 AM")
String _formatTime(DateTime dt) {
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Battery-optimized tracking strategy
class BatteryOptimizedTracker {
  double _lastSpeed = 0;
  LocationData? _lastSignificantPosition;

  /// Calculate optimal tracking interval based on speed
  int calculateOptimalInterval(double currentSpeed) {
    _lastSpeed = currentSpeed;

    if (currentSpeed < AppConfig.movementThresholdMps) {
      // Stationary - update at stationary interval (60 seconds)
      return AppConfig.stationaryIntervalSeconds;
    }

    if (currentSpeed < 2) {
      // Walking (< 7.2 km/h)
      return AppConfig.walkingIntervalSeconds; // 30s
    } else if (currentSpeed < 15) {
      // Running or cycling
      return 20; // 20s
    } else {
      // Driving
      return AppConfig.drivingIntervalSeconds; // 10s
    }
  }

  /// Check if update should be skipped (save battery)
  bool shouldSkipUpdate(LocationData newPos, LocationData? lastPos) {
    if (lastPos == null) {
      _lastSignificantPosition = newPos;
      return false;
    }

    // Calculate distance from last significant position
    final distance = _calculateDistance(
      _lastSignificantPosition?.latitude ?? lastPos.latitude!,
      _lastSignificantPosition?.longitude ?? lastPos.longitude!,
      newPos.latitude!,
      newPos.longitude!,
    );

    // Skip if barely moved and stationary
    if (distance < 10 && (newPos.speed ?? 0) < AppConfig.movementThresholdMps) {
      return true;
    }

    // Update significant position if moved enough
    if (distance >= 50) {
      _lastSignificantPosition = newPos;
    }

    return false;
  }

  /// Get movement status description
  String getMovementStatus() {
    if (_lastSpeed < AppConfig.movementThresholdMps) {
      return 'Stationary';
    } else if (_lastSpeed < 2) {
      return 'Walking';
    } else if (_lastSpeed < 5) {
      return 'Running';
    } else if (_lastSpeed < 15) {
      return 'Cycling';
    } else {
      return 'Driving';
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

/// Location permission helper
class LocationPermissionHelper {
  static final Location _location = Location();

  /// Request all necessary location permissions
  static Future<bool> requestPermissions() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }

    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != PermissionStatus.granted) {
        return false;
      }
    }

    return true;
  }

  /// Check if we have all required permissions
  static Future<bool> hasAllPermissions() async {
    final permission = await _location.hasPermission();
    return permission == PermissionStatus.granted ||
        permission == PermissionStatus.grantedLimited;
  }

  /// Check if we have background location permission
  /// Note: The location package doesn't explicitly distinguish background permission in the enum
  /// but granted usually implies it if requested correctly.
  static Future<bool> hasBackgroundPermission() async {
     final permission = await _location.hasPermission();
     return permission == PermissionStatus.granted;
  }

  /// Open location settings
  static Future<bool> openLocationSettings() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (serviceEnabled) {
      return true;
    }
    serviceEnabled = await _location.requestService();
    if (serviceEnabled) {
      return true;
    }

    // If the system location dialog was dismissed/denied, at least route the
    // user to app settings so permission UX can continue.
    return permission_handler.openAppSettings();
  }

  /// Open app settings
  static Future<bool> openAppSettings() async {
     return permission_handler.openAppSettings();
  }
}
