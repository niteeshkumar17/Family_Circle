import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:location/location.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geocoding/geocoding.dart' hide Location;
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
        initialNotificationTitle: 'Flockar',
        initialNotificationContent: 'Location sharing is active',
        foregroundServiceNotificationId: 889, // Changed from 888 to 889
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

  /// Enable/disable location sharing for a specific family
  void setLocationSharingEnabled(String familyId, bool enabled) {
    _service.invoke('setLocationSharing', {'familyId': familyId, 'enabled': enabled});
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
  // ┌──────────────────────────────────────────────────────────────────────┐
  // │  TOP-LEVEL TRY-CATCH                                                │
  // │  If ANYTHING crashes during init, we write the error to prefs       │
  // │  so we can read it from the app UI for debugging.                   │
  // └──────────────────────────────────────────────────────────────────────┘
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}

  // Grab prefs early for diagnostic breadcrumbs
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_service_status', 'starting');
    await prefs.setString('bg_service_last_start', DateTime.now().toIso8601String());
  } catch (_) {}

  try {
    // Removed initialization notification update

    // Initialize Firebase in background isolate
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Removed Firebase initialization notification update

    // ─── State variables ───
    String? userId;
    String? familyId;
    bool locationSharingEnabled = true;
    int trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
    bool sosMode = false;
    double? lastLat;
    double? lastLng;
    double? lastAccuracy;
    DateTime? lastUpdateTime;
    String? lastAddress; // Cache the address for stationary device
    String? presenceRegisteredUserId;
    int timerTickCount = 0;

    // ─── Services ───
    final battery = Battery();
    final connectivity = Connectivity();
    final database = FirebaseDatabase.instance;
    prefs ??= await SharedPreferences.getInstance();
    final location = Location();

    // ─── Load saved state from SharedPreferences ───
    Future<void> reloadIdentity() async {
      try {
        await prefs!.reload();
      } catch (_) {}
      userId = prefs!.getString('userId');
      familyId = prefs.getString('familyId');
      if (familyId != null) {
        locationSharingEnabled = prefs.getBool('location_sharing_enabled_$familyId') ?? true;
      } else {
        locationSharingEnabled = true;
      }
      // Load last known position from prefs (survives process death)
      lastLat ??= prefs.getDouble('bg_last_lat');
      lastLng ??= prefs.getDouble('bg_last_lng');
    }

    // ─── Save position to prefs (survives process death) ───
    Future<void> savePositionToPrefs(double lat, double lng) async {
      try {
        await prefs!.setDouble('bg_last_lat', lat);
        await prefs.setDouble('bg_last_lng', lng);
      } catch (_) {}
    }

    // ─── Build location payload ───
    Future<Map<String, dynamic>> buildPayload({
      required double lat,
      required double lng,
      double? accuracy,
      double? speed,
      double? heading,
      double? altitude,
    }) async {
      int batteryLevel = 100;
      bool isCharging = false;
      try {
        batteryLevel = await battery.batteryLevel;
        final bs = await battery.batteryState;
        isCharging = bs == BatteryState.charging || bs == BatteryState.full;
      } catch (_) {}

      String networkStatus = 'unknown';
      try {
        final cr = await connectivity.checkConnectivity();
        if (cr.contains(ConnectivityResult.wifi)) {
          networkStatus = 'wifi';
        } else if (cr.contains(ConnectivityResult.mobile)) {
          networkStatus = 'mobile';
        } else {
          networkStatus = 'offline';
        }
      } catch (_) {}

      // Add reverse geocoding
      String? address = lastAddress;
      // Only geocode if we moved significantly or don't have an address yet
      if (address == null || lastLat == null || lastLng == null || 
          (lastLat! - lat).abs() > 0.0001 || (lastLng! - lng).abs() > 0.0001) {
        try {
          final placemarks = await placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 5));
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            final parts = <String>[];
            if (place.name != null && place.name!.isNotEmpty) parts.add(place.name!);
            if (place.subLocality != null && place.subLocality!.isNotEmpty) parts.add(place.subLocality!);
            if (place.locality != null && place.locality!.isNotEmpty) parts.add(place.locality!);
            if (parts.isNotEmpty) {
              address = parts.take(3).join(', ');
              lastAddress = address;
            }
          }
        } catch (_) {}
      }

      return {
        'latitude': lat,
        'longitude': lng,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'address': address,
        'battery': batteryLevel,
        'isCharging': isCharging,
        'networkStatus': networkStatus,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isActive': true,
      };
    }

    // ─── Push to Firebase with cache fallback ───
    Future<bool> pushToFirebase(Map<String, dynamic> data) async {
      if (userId == null || familyId == null) return false;
      try {
        await database.ref('locations/$familyId/$userId').set(data);
        
        // Also save to daily location history
        try {
          final now = DateTime.now();
          final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          final timestamp = data['timestamp'] ?? now.millisecondsSinceEpoch;
          
          await database.ref('locationHistory/$familyId/$userId/$dateKey/$timestamp').set({
            'latitude': data['latitude'],
            'longitude': data['longitude'],
            'accuracy': data['accuracy'],
            'speed': data['speed'],
            'address': data['address'],
            'battery': data['battery'],
            'isCharging': data['isCharging'],
            'timestamp': timestamp,
          });
        } catch (_) {}
        
        return true;
      } catch (_) {
        try {
          await LocationCacheService().cacheLocation(
            userId: userId!,
            familyId: familyId!,
            locationData: data,
          );
        } catch (_) {}
        return false;
      }
    }

    // ─── Presence on-disconnect handler ───
    Future<void> configurePresenceOnDisconnect(String uid) async {
      if (presenceRegisteredUserId != null && presenceRegisteredUserId != uid) {
        try {
          await database.ref('presence/$presenceRegisteredUserId').onDisconnect().cancel();
        } catch (_) {}
      }
      try {
        await database.ref('presence/$uid').onDisconnect().update({
          'online': false,
          'lastSeen': ServerValue.timestamp,
          'appState': 'offline',
        });
        presenceRegisteredUserId = uid;
      } catch (_) {}
    }

    // ─── Initial load ───
    await reloadIdentity();

    if (userId != null && userId!.isNotEmpty) {
      await configurePresenceOnDisconnect(userId!);
    }

    // Show diagnostic notification
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Flockar',
        content: userId != null
            ? 'Location sharing active'
            : 'Waiting for user login...',
      );
    }

    await prefs.setString('bg_service_status', 'initialized');

    // ─── Configure location (non-blocking, errors are OK) ───
    try {
      await location.changeSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        interval: 15000,
      );
      // We are ALREADY running inside a background service.
      // Calling enableBackgroundMode creates a SECOND generic notification ("Location background service running").
      // We do NOT need this.
    } catch (_) {}

    // ─── Location stream listener ───
    StreamSubscription<LocationData>? locationSubscription;
    final batteryOptimizer = BatteryOptimizedTracker();

    void startLocationListening() {
      locationSubscription?.cancel();
      locationSubscription = location.onLocationChanged.listen(
        (position) async {
          if (!locationSharingEnabled || userId == null || familyId == null) return;

          final now = DateTime.now();
          if (lastUpdateTime != null) {
            final elapsed = now.difference(lastUpdateTime!).inSeconds;
            if (elapsed < trackingIntervalSeconds) return;
          }

          if (!sosMode) {
            trackingIntervalSeconds = batteryOptimizer.calculateOptimalInterval(
              position.speed ?? 0,
            );
          }

          try {
            final lat = position.latitude ?? lastLat ?? 0;
            final lng = position.longitude ?? lastLng ?? 0;
            if (lat == 0 && lng == 0) return;

            final data = await buildPayload(
              lat: lat.toDouble(),
              lng: lng.toDouble(),
              accuracy: position.accuracy,
              altitude: position.altitude,
              speed: position.speed,
              heading: position.heading,
            );

            await pushToFirebase(data);
            lastLat = lat.toDouble();
            lastLng = lng.toDouble();
            lastAccuracy = position.accuracy;
            lastUpdateTime = now;
            await savePositionToPrefs(lastLat!, lastLng!);

            service.invoke('locationUpdate', data);
          } catch (_) {}
        },
        onError: (_) {},
        cancelOnError: false,
      );
    }

    startLocationListening();

    // ─── Service command handlers ───
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((_) => service.setAsForegroundService());
      service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
    }

    service.on('stopService').listen((_) async {
      locationSubscription?.cancel();
      if (userId != null && userId!.isNotEmpty) {
        try {
          await database.ref('presence/$userId').set({
            'online': false,
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
            'appState': 'stopped',
          });
          await database.ref('presence/$userId').onDisconnect().cancel();
        } catch (_) {}
        presenceRegisteredUserId = null;
      }
      service.stopSelf();
    });

    service.on('setUserId').listen((event) async {
      userId = event?['userId'];
      if (userId == null || userId!.isEmpty) {
        final prev = presenceRegisteredUserId;
        if (prev != null) {
          try {
            await database.ref('presence/$prev').set({
              'online': false,
              'lastSeen': DateTime.now().millisecondsSinceEpoch,
              'appState': 'signed_out',
            });
            await database.ref('presence/$prev').onDisconnect().cancel();
          } catch (_) {}
          presenceRegisteredUserId = null;
        }
        try { await prefs!.remove('userId'); } catch (_) {}
      } else {
        try { await prefs!.setString('userId', userId!); } catch (_) {}
        await configurePresenceOnDisconnect(userId!);
      }
    });

    service.on('setFamilyId').listen((event) async {
      familyId = event?['familyId'];
      if (familyId == null || familyId!.isEmpty) {
        try { await prefs!.remove('familyId'); } catch (_) {}
        locationSharingEnabled = true;
      } else {
        try { await prefs!.setString('familyId', familyId!); } catch (_) {}
        locationSharingEnabled = prefs!.getBool('location_sharing_enabled_$familyId') ?? true;
      }
    });

    service.on('setLocationSharing').listen((event) async {
      final targetFamilyId = event?['familyId'];
      final enabled = event?['enabled'] ?? true;
      if (targetFamilyId != null) {
        try { await prefs!.setBool('location_sharing_enabled_$targetFamilyId', enabled); } catch (_) {}
        if (familyId == targetFamilyId) {
          locationSharingEnabled = enabled;
        }
      }
    });

    service.on('setInterval').listen((event) {
      trackingIntervalSeconds = event?['seconds'] ?? AppConfig.locationUpdateIntervalSeconds;
    });

    service.on('enableSOSMode').listen((_) {
      sosMode = true;
      trackingIntervalSeconds = AppConfig.sosTrackingIntervalSeconds;
    });

    service.on('disableSOSMode').listen((_) {
      sosMode = false;
      trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
    });

    // ════════════════════════════════════════════════════════════════════════
    // KEEP-ALIVE TIMER — runs every 60 seconds
    //
    // ARCHITECTURE:
    //  Step 1: Update notification (proves timer is alive)
    //  Step 2: Reload identity from prefs
    //  Step 3: Push presence heartbeat (no GPS needed)
    //  Step 4: Try GPS → push fresh coords, OR push last-known coords
    //
    // The timer NEVER blocks on GPS for more than 15 seconds total.
    // Even if GPS fails, we push last-known coords with a fresh timestamp.
    // ════════════════════════════════════════════════════════════════════════
    Timer.periodic(const Duration(minutes: 1), (timer) async {
      timerTickCount++;

      // Step 1: Update notification FIRST (diagnostic — proves timer fires)
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Flockar',
          content: 'Location sharing active',
        );
      }

      // Step 2: Reload identity (handles race condition where main app
      // wrote userId/familyId to prefs after this isolate started)
      await reloadIdentity();

      if (userId == null || userId!.isEmpty) {
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Flockar',
            content: 'Waiting for user login...',
          );
        }
        try {
          await prefs!.setString('bg_service_status', 'no_user_id');
        } catch (_) {}
        return;
      }

      final now = DateTime.now();

      // Step 3: Presence heartbeat (always runs, independent of GPS)
      try {
        await database.ref('presence/$userId').set({
          'online': true,
          'lastSeen': now.millisecondsSinceEpoch,
          'appState': 'background',
        });
        await configurePresenceOnDisconnect(userId!);
      } catch (_) {}

      if (!locationSharingEnabled || familyId == null) {
          // Removed paused notification update
        return;
      }

      // Step 4: Try GPS with SHORT timeout, then push whatever we have
      double? lat = lastLat;
      double? lng = lastLng;
      double? accuracy = lastAccuracy;
      double? speed;
      double? heading;
      double? altitude;
      bool gpsFresh = false;

      try {
        final pos = await location.getLocation().timeout(
          const Duration(seconds: 15),
        );
        if (pos.latitude != null && pos.longitude != null) {
          lat = pos.latitude!;
          lng = pos.longitude!;
          accuracy = pos.accuracy;
          speed = pos.speed;
          heading = pos.heading;
          altitude = pos.altitude;
          gpsFresh = true;
        }
      } catch (_) {
        // GPS failed — will use last-known coordinates below
      }

      // Push location (fresh or stale coords, always fresh timestamp)
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        final data = await buildPayload(
          lat: lat,
          lng: lng,
          accuracy: accuracy,
          speed: speed,
          heading: heading,
          altitude: altitude,
        );

        final ok = await pushToFirebase(data);

        if (gpsFresh) {
          lastLat = lat;
          lastLng = lng;
          lastAccuracy = accuracy;
          await savePositionToPrefs(lat, lng);
        }
        lastUpdateTime = now;

        // Removed location push notification update

        service.invoke('locationUpdate', data);

        try {
          await prefs!.setString('bg_service_status', 'location_pushed');
          await prefs.setString('bg_service_last_push', now.toIso8601String());
        } catch (_) {}
      } else {
        // No coordinates at all (neither GPS nor cached)
        // Removed waiting for GPS notification update
        try {
          await prefs!.setString('bg_service_status', 'no_coordinates');
        } catch (_) {}
      }
    });

    // ─── Connectivity listener — upload cached locations ───
    connectivity.onConnectivityChanged.listen((result) async {
      final isOnline = result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile);
      if (!isOnline || userId == null || familyId == null) return;

      try {
        final cache = LocationCacheService();
        final pendingCount = await cache.getPendingCount();
        if (pendingCount == 0) return;

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
            } catch (_) { break; }
          }

          if (syncedIds.isNotEmpty) await cache.markAsSynced(syncedIds);
          if (syncedIds.length < batch.length) break;
        }
      } catch (_) {}
    });

  } catch (e) {
    // ─── CATASTROPHIC ERROR — write to prefs for debugging ───
    try {
      prefs ??= await SharedPreferences.getInstance();
      await prefs.setString('bg_service_status', 'CRASHED');
      await prefs.setString('bg_service_error', e.toString());
      await prefs.setString('bg_service_crash_time', DateTime.now().toIso8601String());
    } catch (_) {}

    // Still try to show error in notification
    // Removed error notification update
  }
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
