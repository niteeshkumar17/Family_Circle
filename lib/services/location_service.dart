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

/// Geofence Monitoring Service
class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  final _eventController = StreamController<GeofenceEvent>.broadcast();
  final Map<String, bool> _geofenceStates = {}; // geofenceId -> isInside

  /// Stream of geofence events
  Stream<GeofenceEvent> get eventStream => _eventController.stream;

  /// Check location against geofences
  List<GeofenceEvent> checkGeofences(
    LocationModel location,
    List<GeofenceModel> geofences,
    String userName,
  ) {
    final events = <GeofenceEvent>[];

    for (final geofence in geofences) {
      if (!geofence.isActive) continue;

      // Check if member is monitored
      if (geofence.monitoredMembers.isNotEmpty &&
          !geofence.monitoredMembers.contains(location.userId)) {
        continue;
      }

      final isInside = geofence.containsLocation(location);
      final wasInside = _geofenceStates[geofence.id] ?? false;

      if (isInside != wasInside) {
        // State changed
        final eventType = isInside
            ? GeofenceEventType.entry
            : GeofenceEventType.exit;

        // Check quiet hours
        if (geofence.settings.isInQuietHours()) {
          continue; // Skip notification during quiet hours
        }

        final event = GeofenceEvent(
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

        events.add(event);
        _eventController.add(event);

        // Update state
        _geofenceStates[geofence.id] = isInside;
      }
    }

    return events;
  }

  /// Reset geofence states (e.g., when switching families)
  void resetStates() {
    _geofenceStates.clear();
  }

  /// Dispose
  void dispose() {
    _eventController.close();
  }
}
