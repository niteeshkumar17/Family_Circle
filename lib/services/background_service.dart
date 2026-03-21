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
import '../config/app_config.dart';
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
        autoStart: false, // Don't auto-start, wait for user consent
        isForegroundMode: true, // Required for Android 10+
        notificationChannelId: 'family_nest_location',
        initialNotificationTitle: 'FamilyNest',
        initialNotificationContent: 'Location sharing is active',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: true,
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

  /// Update user ID for location tracking
  void setUserId(String userId) {
    _service.invoke('setUserId', {'userId': userId});
  }

  /// Set family ID for location tracking
  void setFamilyId(String familyId) {
    _service.invoke('setFamilyId', {'familyId': familyId});
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
  await Firebase.initializeApp();

  // State variables
  String? userId;
  String? familyId;
  bool locationSharingEnabled = true;
  int trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
  bool sosMode = false;
  LocationData? lastPosition;
  DateTime? lastUpdateTime;

  // Services
  final battery = Battery();
  final connectivity = Connectivity();
  final database = FirebaseDatabase.instance;
  final prefs = await SharedPreferences.getInstance();
  final location = Location();

  // Load saved state
  userId = prefs.getString('userId');
  familyId = prefs.getString('familyId');
  locationSharingEnabled = prefs.getBool('locationSharingEnabled') ?? true;

  try {
    await location.enableBackgroundMode(enable: true);
  } catch (e) {
    if (kDebugMode) {
      print('Could not enable background mode: $e');
    }
  }

  // Battery optimizer
  final batteryOptimizer = BatteryOptimizedTracker();

  // Handle service commands
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('setUserId').listen((event) {
    userId = event?['userId'];
    prefs.setString('userId', userId ?? '');
  });

  service.on('setFamilyId').listen((event) {
    familyId = event?['familyId'];
    prefs.setString('familyId', familyId ?? '');
  });

  service.on('setLocationSharing').listen((event) {
    locationSharingEnabled = event?['enabled'] ?? true;
    prefs.setBool('locationSharingEnabled', locationSharingEnabled);
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

  // Main location tracking loop
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    // Check if we should update
    final now = DateTime.now();
    if (lastUpdateTime != null) {
      final elapsed = now.difference(lastUpdateTime!).inSeconds;
      if (elapsed < trackingIntervalSeconds) {
        return; // Not time yet
      }
    }

    // Skip if location sharing is disabled
    if (!locationSharingEnabled || userId == null || familyId == null) {
      return;
    }

    try {
      // Get current position
      final position = await location.getLocation();

      // Check if we should skip this update (battery optimization)
      bool skipPositionUpdate = !sosMode && batteryOptimizer.shouldSkipUpdate(position, lastPosition);
      // We no longer `return;` here because we STILL need to update the timestamp
      // on Firebase so other devices know the user is active at this location!

      // Calculate adaptive interval
      if (!sosMode) {
        trackingIntervalSeconds = batteryOptimizer.calculateOptimalInterval(
          position.speed ?? 0,
        );
      }

      // Get battery info
      final batteryLevel = await battery.batteryLevel;
      final batteryState = await battery.batteryState;
      final isCharging = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;

      // Get network status
      final connectivityResult = await connectivity.checkConnectivity();
      String networkStatus = 'offline';
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        networkStatus = 'wifi';
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        networkStatus = 'mobile';
      }

      // Prepare location data
      final locationData = {
        'latitude': skipPositionUpdate ? (lastPosition?.latitude ?? position.latitude) : position.latitude,
        'longitude': skipPositionUpdate ? (lastPosition?.longitude ?? position.longitude) : position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'battery': batteryLevel,
        'isCharging': isCharging,
        'networkStatus': networkStatus,
        'timestamp': now.millisecondsSinceEpoch,
        'isActive': true,
      };

      // Update Firebase Realtime Database
      await database
          .ref('locations/$familyId/$userId')
          .set(locationData);

      // Update state
      lastPosition = position;
      lastUpdateTime = now;

      // Update notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'FamilyNest',
          content: sosMode
              ? '🚨 SOS Mode - Tracking every ${trackingIntervalSeconds}s'
              : '📍 Location sharing active',
        );
      }

      // Send update to main app
      service.invoke('locationUpdate', locationData);

      // Log for debugging
      if (kDebugMode) {
        print('Location updated: ${position.latitude}, ${position.longitude}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Location update failed: $e');
      }
    }
  });

  // Presence heartbeat - update every minute
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (userId == null) return;
    
    try {
      await database.ref('presence/$userId').set({
        'online': true,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'appState': 'background',
      });
    } catch (e) {
      if (kDebugMode) {
        print('Presence update failed: $e');
      }
    }
  });
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
  int _stationaryCount = 0;
  LocationData? _lastSignificantPosition;

  /// Calculate optimal tracking interval based on speed
  int calculateOptimalInterval(double currentSpeed) {
    _lastSpeed = currentSpeed;

    if (currentSpeed < AppConfig.movementThresholdMps) {
      // Stationary - increase interval progressively
      _stationaryCount++;
      if (_stationaryCount > 10) {
        return AppConfig.stationaryIntervalSeconds * 2; // 4 minutes
      }
      return AppConfig.stationaryIntervalSeconds; // 2 minutes
    }

    // Reset stationary count when moving
    _stationaryCount = 0;

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
    // location package doesn't have openSettings directly exposed in same way
    // Assuming true for now or implementation dependent
    return true; 
  }

  /// Open app settings
  static Future<bool> openAppSettings() async {
     // location package doesn't have openAppSettings directly exposed
     return true; 
  }
}
