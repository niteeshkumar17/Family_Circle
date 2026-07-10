import 'dart:async';
import 'package:location/location.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geocoding/geocoding.dart' hide Location;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../data/models/location_model.dart';
import '../data/models/geofence_model.dart';
import 'dart:math' as math;

/// Location Service
/// 
/// Handles foreground location tracking and geofence monitoring
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final Location _location = Location();
  final Battery _battery = Battery();
  
  StreamSubscription<LocationData>? _positionSubscription;
  final _locationController = StreamController<LocationModel>.broadcast();
  
  String? _userId;
  String? _familyId;
  LocationData? _lastPosition;
  List<GeofenceModel> _activeGeofences = [];
  final Map<String, bool> _foregroundGeofenceStates = {};
  int _currentBattery = 100;
  bool _isCharging = false;
  String _networkStatus = 'unknown';

  /// Stream of location updates
  Stream<LocationModel> get locationStream => _locationController.stream;

  /// Initialize the location service
  Future<void> initialize({
    required String userId,
    required String familyId,
  }) async {
    _userId = userId;
    _familyId = familyId;
  }

  /// Check and request location permissions
  Future<bool> checkPermissions() async {
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

  /// Start foreground location tracking
  Future<void> startTracking() async {
    if (_userId == null || _familyId == null) {
      throw Exception('LocationService not initialized');
    }

    try {
      await _location.enableBackgroundMode(enable: true);
    } catch (e) {
      // Background mode may not be supported or permitted
    }

    // Configure location settings
    await _location.changeSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // meters
      interval: 5000,
    );

    // Start listening to position updates
    _positionSubscription = _location.onLocationChanged.listen(_onPositionUpdate);
  }

  /// Stop location tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Handle position updates
  Future<void> _onPositionUpdate(LocationData position) async {
    _lastPosition = position;

    // Get battery info
    try {
      _currentBattery = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      _isCharging = batteryState == BatteryState.charging || 
                    batteryState == BatteryState.full;
    } catch (e) {
      // Keep previous values
    }
    
    // Get network status
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.wifi)) {
        _networkStatus = 'wifi';
      } else if (connectivity.contains(ConnectivityResult.mobile)) {
        _networkStatus = 'mobile';
      } else {
        _networkStatus = 'offline';
      }
    } catch (e) {
      _networkStatus = 'unknown';
    }

    // Get address from coordinates
    String? address;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude!,
        position.longitude!,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        address = _formatAddress(place);
      }
    } catch (e) {
      // Geocoding failed, continue without address
    }

    // Create location model
    final location = LocationModel(
      userId: _userId!,
      latitude: position.latitude!,
      longitude: position.longitude!,
      accuracy: position.accuracy ?? 0,
      altitude: position.altitude ?? 0,
      speed: position.speed ?? 0,
      heading: position.heading ?? 0,
      address: address,
      batteryLevel: _currentBattery,
      isCharging: _isCharging,
      networkStatus: _networkStatus,
      timestamp: DateTime.now(),
      isActive: true,
    );

    // Emit to stream
    _locationController.add(location);
    
    // Push to Firebase Realtime Database
    await _pushLocationToFirebase(location);

    // Check geofences
    _checkGeofences(location);
  }
  
  /// Push location data to Firebase Realtime Database
  Future<void> _pushLocationToFirebase(LocationModel location) async {
    if (_familyId == null || _userId == null) return;
    
    try {
      await _database
          .ref('locations/$_familyId/$_userId')
          .set(location.toRealtimeDb());
    } catch (e) {
      // Failed to push, will retry on next update
    }
  }

  /// Format address from placemark
  String _formatAddress(Placemark place) {
    final parts = <String>[];
    
    if (place.name != null && place.name!.isNotEmpty) {
      parts.add(place.name!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }
    
    return parts.take(3).join(', ');
  }

  /// Get current location once
  Future<LocationModel> getCurrentLocation() async {
    final position = await _location.getLocation();

    String? address;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude!,
        position.longitude!,
      );
      if (placemarks.isNotEmpty) {
        address = _formatAddress(placemarks.first);
      }
    } catch (e) {
      // Continue without address
    }

    return LocationModel(
      userId: _userId ?? '',
      latitude: position.latitude!,
      longitude: position.longitude!,
      accuracy: position.accuracy ?? 0,
      altitude: position.altitude ?? 0,
      speed: position.speed ?? 0,
      heading: position.heading ?? 0,
      address: address,
      timestamp: DateTime.now(),
      isActive: true,
    );
  }

  /// Set active geofences for monitoring
  void setGeofences(List<GeofenceModel> geofences) {
    _activeGeofences = geofences.where((g) => g.isActive).toList();

    // Remove stale geofence states that are no longer active.
    final activeIds = _activeGeofences.map((g) => g.id).toSet();
    _foregroundGeofenceStates.removeWhere((geofenceId, _) => !activeIds.contains(geofenceId));
  }

  /// Check if location triggers any geofences
  void _checkGeofences(LocationModel location) {
    for (final geofence in _activeGeofences) {
      final isInside = geofence.containsLocation(location);
      final wasInside = _foregroundGeofenceStates[geofence.id];

      // Initialize without generating a false transition event.
      if (wasInside == null) {
        _foregroundGeofenceStates[geofence.id] = isInside;
        continue;
      }

      if (wasInside != isInside) {
        _foregroundGeofenceStates[geofence.id] = isInside;
      }
    }
  }

  /// Listen to a family member's location
  Stream<LocationModel> listenToMemberLocation(String memberId) {
    if (_familyId == null) {
      throw Exception('Family ID not set');
    }

    return _database
        .ref('locations/$_familyId/$memberId')
        .onValue
        .map((event) {
          if (event.snapshot.value == null) {
            throw Exception('No location data');
          }
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          return LocationModel.fromRealtimeDb(data, memberId);
        });
  }

  /// Listen to all family members' locations
  Stream<Map<String, LocationModel>> listenToFamilyLocations() {
    if (_familyId == null) {
      throw Exception('Family ID not set');
    }

    return _database
        .ref('locations/$_familyId')
        .onValue
        .map((event) {
          final result = <String, LocationModel>{};
          if (event.snapshot.value != null) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            data.forEach((key, value) {
              if (value is Map) {
                result[key.toString()] = LocationModel.fromRealtimeDb(
                  value,
                  key.toString(),
                );
              }
            });
          }
          return result;
        });
  }

  /// Get last known location from cache
  LocationData? get lastKnownPosition => _lastPosition;

  /// Calculate distance between two locations using Haversine formula
  double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
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

  /// Dispose
  void dispose() {
    stopTracking();
    _locationController.close();
  }
}

/// Geofence Monitoring Service with hysteresis and dwell-time logic
class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  final _eventController = StreamController<GeofenceEvent>.broadcast();

  /// Per-geofence tracking state: geofenceId -> state
  final Map<String, _GeofenceTrackingState> _trackingStates = {};

  /// Stream of geofence events
  Stream<GeofenceEvent> get eventStream => _eventController.stream;

  /// Check location against geofences using hysteresis + dwell-time logic.
  ///
  /// **Hysteresis**: Entry requires distance < (radius - cushion). Exit requires
  /// distance > (radius + cushion). This creates a dead zone at the boundary
  /// where GPS drift won't trigger false transitions.
  ///
  /// **Dwell-Time**: After a boundary crossing is detected, the alert only fires
  /// once the user has remained in the new state for [dwellTimeSeconds]. If they
  /// bounce back before the timer expires, the pending transition is cancelled.
  List<GeofenceEvent> checkGeofences(
    LocationModel location,
    List<GeofenceModel> geofences,
    String userName,
  ) {
    final events = <GeofenceEvent>[];
    final now = DateTime.now();

    for (final geofence in geofences) {
      if (!geofence.isActive) continue;

      // Check if member is monitored
      if (geofence.monitoredMembers.isNotEmpty &&
          !geofence.monitoredMembers.contains(location.userId)) {
        continue;
      }

      // Get or create tracking state for this geofence
      final state = _trackingStates.putIfAbsent(
        geofence.id,
        () => _GeofenceTrackingState(),
      );

      // Use hysteresis thresholds
      final isDeepInside = geofence.isDeepInside(location);
      final isClearlyOutside = geofence.isClearlyOutside(location);
      final dwellSeconds = geofence.settings.effectiveDwellTimeSeconds;

      // --- State machine ---

      if (!state.isInitialized) {
        // First check: initialize without generating events
        state.isInside = geofence.containsLocation(location);
        state.isInitialized = true;
        continue;
      }

      if (state.isInside) {
        // Currently INSIDE — check for exit
        if (isClearlyOutside) {
          if (state.pendingTransitionTime == null) {
            // Start exit dwell timer
            state.pendingTransitionTime = now;
            state.pendingIsEntry = false;
          } else if (!state.pendingIsEntry! &&
              now.difference(state.pendingTransitionTime!).inSeconds >= dwellSeconds) {
            // Dwell time elapsed — confirm exit
            state.isInside = false;
            state.pendingTransitionTime = null;
            state.pendingIsEntry = null;
            state.dwellAlertFired = false;

            if (geofence.settings.notifyOnExit && !geofence.settings.isInQuietHours()) {
              final event = _createEvent(geofence, location, userName, GeofenceEventType.exit);
              events.add(event);
              _eventController.add(event);
            }
          }
        } else {
          // User is still inside (or in dead zone) — cancel any pending exit
          if (state.pendingTransitionTime != null && state.pendingIsEntry == false) {
            state.pendingTransitionTime = null;
            state.pendingIsEntry = null;
          }

          // Check for dwell alert (sustained presence)
          if (!state.dwellAlertFired && state.entryConfirmedTime != null) {
            if (now.difference(state.entryConfirmedTime!).inSeconds >= dwellSeconds) {
              state.dwellAlertFired = true;
              if (geofence.settings.notifyOnDwell && !geofence.settings.isInQuietHours()) {
                final event = _createEvent(geofence, location, userName, GeofenceEventType.dwell);
                events.add(event);
                _eventController.add(event);
              }
            }
          }
        }
      } else {
        // Currently OUTSIDE — check for entry
        if (isDeepInside) {
          if (state.pendingTransitionTime == null) {
            // Start entry dwell timer
            state.pendingTransitionTime = now;
            state.pendingIsEntry = true;
          } else if (state.pendingIsEntry! &&
              now.difference(state.pendingTransitionTime!).inSeconds >= dwellSeconds) {
            // Dwell time elapsed — confirm entry
            state.isInside = true;
            state.entryConfirmedTime = now;
            state.pendingTransitionTime = null;
            state.pendingIsEntry = null;
            state.dwellAlertFired = false;

            if (geofence.settings.notifyOnEntry && !geofence.settings.isInQuietHours()) {
              final event = _createEvent(geofence, location, userName, GeofenceEventType.entry);
              events.add(event);
              _eventController.add(event);
            }
          }
        } else {
          // User is still outside (or in dead zone) — cancel any pending entry
          if (state.pendingTransitionTime != null && state.pendingIsEntry == true) {
            state.pendingTransitionTime = null;
            state.pendingIsEntry = null;
          }
        }
      }
    }

    return events;
  }

  GeofenceEvent _createEvent(
    GeofenceModel geofence,
    LocationModel location,
    String userName,
    GeofenceEventType eventType,
  ) {
    return GeofenceEvent(
      id: '${geofence.id}_${DateTime.now().millisecondsSinceEpoch}',
      geofenceId: geofence.id,
      geofenceName: geofence.name,
      userId: location.userId,
      userName: userName,
      eventType: eventType,
      timestamp: DateTime.now(),
      latitude: location.latitude,
      longitude: location.longitude,
    );
  }

  /// Reset geofence states (e.g., when switching families)
  void resetStates() {
    _trackingStates.clear();
  }

  /// Dispose
  void dispose() {
    _eventController.close();
  }
}

/// Internal tracking state for a single geofence
class _GeofenceTrackingState {
  bool isInitialized = false;
  bool isInside = false;

  /// When a boundary crossing was first detected (dwell timer start)
  DateTime? pendingTransitionTime;

  /// true = pending entry, false = pending exit, null = no pending transition
  bool? pendingIsEntry;

  /// When entry was confirmed (for dwell alert timing)
  DateTime? entryConfirmedTime;

  /// Whether the dwell alert has already been fired for the current visit
  bool dwellAlertFired = false;
}
