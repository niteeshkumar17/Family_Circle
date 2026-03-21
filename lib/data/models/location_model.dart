import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

part 'location_model.g.dart';

@JsonSerializable(explicitToJson: true)
class LocationModel {
  final String? id;
  final String userId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final String? address;
  final int batteryLevel;
  final bool isCharging;
  final String networkStatus; // wifi, mobile, offline
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime timestamp;
  @JsonKey(fromJson: _sourceFromString, toJson: _sourceToString)
  final LocationSource source;
  final bool isActive;

  LocationModel({
    this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
    this.altitude,
    this.speed,
    this.heading,
    this.address,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.networkStatus = 'unknown',
    required this.timestamp,
    this.source = LocationSource.fused,
    this.isActive = true,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) =>
      _$LocationModelFromJson(json);

  Map<String, dynamic> toJson() => _$LocationModelToJson(this);

  factory LocationModel.fromRealtimeDb(Map<dynamic, dynamic> data, String oderId) {
    return LocationModel(
      userId: oderId,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0,
      altitude: (data['altitude'] as num?)?.toDouble(),
      speed: (data['speed'] as num?)?.toDouble(),
      heading: (data['heading'] as num?)?.toDouble(),
      address: data['address'] as String?,
      batteryLevel: data['battery'] as int? ?? 100,
      isCharging: data['isCharging'] as bool? ?? false,
      networkStatus: data['networkStatus'] as String? ?? 'unknown',
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toRealtimeDb() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'address': address,
      'battery': batteryLevel,
      'isCharging': isCharging,
      'networkStatus': networkStatus,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isActive': isActive,
    };
  }

  LocationModel copyWith({
    String? id,
    String? userId,
    double? latitude,
    double? longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    String? address,
    int? batteryLevel,
    bool? isCharging,
    String? networkStatus,
    DateTime? timestamp,
    LocationSource? source,
    bool? isActive,
  }) {
    return LocationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      address: address ?? this.address,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      networkStatus: networkStatus ?? this.networkStatus,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Alias for batteryLevel
  int get battery => batteryLevel;

  /// Calculate distance to another location in meters
  double distanceTo(LocationModel other) {
    return _calculateHaversineDistance(
      latitude, longitude,
      other.latitude, other.longitude,
    );
  }

  /// Check if location is stale (older than threshold)
  bool isStale({Duration threshold = const Duration(minutes: 5)}) {
    return DateTime.now().difference(timestamp) > threshold;
  }

  /// Get formatted time ago string
  String get timeAgo {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  static double _calculateHaversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) * _cos(_toRadians(lat2)) *
        _sin(dLon / 2) * _sin(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double deg) => deg * 3.141592653589793 / 180;
  static double _sin(double x) => _sinCos(x, true);
  static double _cos(double x) => _sinCos(x, false);
  static double _sqrt(double x) => x >= 0 ? _newtonSqrt(x) : 0;
  static double _atan2(double y, double x) {
    // Simplified atan2 using dart:math would be better, but keeping pure
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }
  static double _sinCos(double x, bool isSin) {
    // Taylor series approximation
    x = x % (2 * 3.141592653589793);
    if (!isSin) x += 3.141592653589793 / 2;
    double result = 0, term = x;
    for (int n = 1; n <= 10; n++) {
      result += term;
      term *= -x * x / ((2 * n) * (2 * n + 1));
    }
    return result;
  }
  static double _newtonSqrt(double x) {
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
  static double _atan(double x) {
    // Taylor series for small x
    if (x.abs() > 1) {
      return (x > 0 ? 1 : -1) * (3.141592653589793 / 2 - _atan(1 / x));
    }
    double result = 0, term = x;
    for (int n = 0; n < 20; n++) {
      result += term / (2 * n + 1) * (n % 2 == 0 ? 1 : -1);
      term *= x * x;
    }
    return result;
  }

  static DateTime _dateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return DateTime.now();
  }

  static dynamic _dateTimeToTimestamp(DateTime dateTime) {
    return Timestamp.fromDate(dateTime);
  }

  static LocationSource _sourceFromString(String? source) {
    return LocationSource.values.firstWhere(
      (e) => e.name == source,
      orElse: () => LocationSource.fused,
    );
  }

  static String _sourceToString(LocationSource source) => source.name;
}

enum LocationSource { gps, network, fused, passive }

@JsonSerializable(explicitToJson: true)
class LocationHistoryModel {
  final String userId;
  @JsonKey(fromJson: LocationModel._dateTimeFromTimestamp, toJson: LocationModel._dateTimeToTimestamp)
  final DateTime date;
  final List<LocationPoint> points;
  final double totalDistance;
  final List<PlaceVisit> placeVisits;

  LocationHistoryModel({
    required this.userId,
    required this.date,
    this.points = const [],
    this.totalDistance = 0,
    this.placeVisits = const [],
  });

  factory LocationHistoryModel.fromJson(Map<String, dynamic> json) =>
      _$LocationHistoryModelFromJson(json);

  Map<String, dynamic> toJson() => _$LocationHistoryModelToJson(this);
}

@JsonSerializable()
class LocationPoint {
  final double lat;
  final double lng;
  @JsonKey(fromJson: LocationModel._dateTimeFromTimestamp, toJson: LocationModel._dateTimeToTimestamp)
  final DateTime time;

  LocationPoint({
    required this.lat,
    required this.lng,
    required this.time,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) =>
      _$LocationPointFromJson(json);

  Map<String, dynamic> toJson() => _$LocationPointToJson(this);
}

@JsonSerializable()
class PlaceVisit {
  final String? placeId;
  final String name;
  final double latitude;
  final double longitude;
  @JsonKey(fromJson: LocationModel._dateTimeFromTimestamp, toJson: LocationModel._dateTimeToTimestamp)
  final DateTime arrivalTime;
  @JsonKey(fromJson: _nullableDateTimeFromTimestamp, toJson: _nullableDateTimeToTimestamp)
  final DateTime? departureTime;

  PlaceVisit({
    this.placeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.arrivalTime,
    this.departureTime,
  });

  factory PlaceVisit.fromJson(Map<String, dynamic> json) =>
      _$PlaceVisitFromJson(json);

  Map<String, dynamic> toJson() => _$PlaceVisitToJson(this);

  Duration get duration {
    final end = departureTime ?? DateTime.now();
    return end.difference(arrivalTime);
  }

  String get formattedDuration {
    final d = duration;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    return '${d.inMinutes}m';
  }

  static DateTime? _nullableDateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    return LocationModel._dateTimeFromTimestamp(timestamp);
  }

  static dynamic _nullableDateTimeToTimestamp(DateTime? dateTime) {
    if (dateTime == null) return null;
    return LocationModel._dateTimeToTimestamp(dateTime);
  }
}
