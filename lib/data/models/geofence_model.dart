import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'location_model.dart';

part 'geofence_model.g.dart';

@JsonSerializable(explicitToJson: true)
class GeofenceModel {
  final String id;
  final String familyId;
  final String name;
  final String? icon;
  @JsonKey(fromJson: _typeFromString, toJson: _typeToString)
  final GeofenceType type;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String? address;
  final String createdBy;
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime createdAt;
  final bool isActive;
  final GeofenceSettings settings;
  final List<String> monitoredMembers; // empty = all members

  GeofenceModel({
    required this.id,
    required this.familyId,
    required this.name,
    this.icon,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
    this.address,
    required this.createdBy,
    required this.createdAt,
    this.isActive = true,
    required this.settings,
    this.monitoredMembers = const [],
  });

  factory GeofenceModel.fromJson(Map<String, dynamic> json) =>
      _$GeofenceModelFromJson(json);

  Map<String, dynamic> toJson() => _$GeofenceModelToJson(this);

  factory GeofenceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GeofenceModel.fromJson({...data, 'id': doc.id});
  }

  GeofenceModel copyWith({
    String? id,
    String? familyId,
    String? name,
    String? icon,
    GeofenceType? type,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? address,
    String? createdBy,
    DateTime? createdAt,
    bool? isActive,
    GeofenceSettings? settings,
    List<String>? monitoredMembers,
  }) {
    return GeofenceModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      address: address ?? this.address,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      settings: settings ?? this.settings,
      monitoredMembers: monitoredMembers ?? this.monitoredMembers,
    );
  }

  /// Check if a location is inside this geofence
  bool containsLocation(LocationModel location) {
    return _calculateDistance(
      latitude, longitude,
      location.latitude, location.longitude,
    ) <= radiusMeters;
  }

  /// Check if coordinates are inside this geofence
  bool containsCoordinates(double lat, double lng) {
    return _calculateDistance(latitude, longitude, lat, lng) <= radiusMeters;
  }

  /// Get icon for geofence type
  IconData get typeIcon {
    switch (type) {
      case GeofenceType.home:
        return Icons.home_rounded;
      case GeofenceType.school:
        return Icons.school_rounded;
      case GeofenceType.office:
        return Icons.work_rounded;
      case GeofenceType.custom:
        return Icons.place_rounded;
    }
  }

  /// Get color for geofence type
  Color get typeColor {
    switch (type) {
      case GeofenceType.home:
        return const Color(0xFF22C55E);
      case GeofenceType.school:
        return const Color(0xFF3B82F6);
      case GeofenceType.office:
        return const Color(0xFFF59E0B);
      case GeofenceType.custom:
        return const Color(0xFF8B5CF6);
    }
  }

  static double _calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;

  static DateTime _dateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now();
  }

  static dynamic _dateTimeToTimestamp(DateTime dateTime) {
    return Timestamp.fromDate(dateTime);
  }

  static GeofenceType _typeFromString(String type) {
    return GeofenceType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => GeofenceType.custom,
    );
  }

  static String _typeToString(GeofenceType type) => type.name;
}

enum GeofenceType { home, school, office, custom }

@JsonSerializable(explicitToJson: true)
class GeofenceSettings {
  final bool notifyOnEntry;
  final bool notifyOnExit;
  final List<String> notifyMembers; // admin IDs to notify, empty = all admins
  final bool enableQuietHours;
  @JsonKey(fromJson: _timeOfDayFromJson, toJson: _timeOfDayToJson)
  final TimeOfDay? quietStart;
  @JsonKey(fromJson: _timeOfDayFromJson, toJson: _timeOfDayToJson)
  final TimeOfDay? quietEnd;

  GeofenceSettings({
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.notifyMembers = const [],
    this.enableQuietHours = false,
    this.quietStart,
    this.quietEnd,
  });

  factory GeofenceSettings.fromJson(Map<String, dynamic> json) =>
      _$GeofenceSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$GeofenceSettingsToJson(this);

  GeofenceSettings copyWith({
    bool? notifyOnEntry,
    bool? notifyOnExit,
    List<String>? notifyMembers,
    bool? enableQuietHours,
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) {
    return GeofenceSettings(
      notifyOnEntry: notifyOnEntry ?? this.notifyOnEntry,
      notifyOnExit: notifyOnExit ?? this.notifyOnExit,
      notifyMembers: notifyMembers ?? this.notifyMembers,
      enableQuietHours: enableQuietHours ?? this.enableQuietHours,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
    );
  }

  /// Check if currently in quiet hours
  bool isInQuietHours() {
    if (!enableQuietHours || quietStart == null || quietEnd == null) {
      return false;
    }
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = quietStart!.hour * 60 + quietStart!.minute;
    final endMinutes = quietEnd!.hour * 60 + quietEnd!.minute;

    if (startMinutes <= endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
    } else {
      // Overnight quiet hours (e.g., 22:00 - 07:00)
      return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
    }
  }

  static TimeOfDay? _timeOfDayFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return TimeOfDay(hour: json['hour'] as int, minute: json['minute'] as int);
  }

  static Map<String, dynamic>? _timeOfDayToJson(TimeOfDay? time) {
    if (time == null) return null;
    return {'hour': time.hour, 'minute': time.minute};
  }
}

@JsonSerializable(explicitToJson: true)
class GeofenceEvent {
  final String id;
  final String geofenceId;
  final String geofenceName;
  final String userId;
  final String userName;
  @JsonKey(fromJson: _eventTypeFromString, toJson: _eventTypeToString)
  final GeofenceEventType eventType;
  @JsonKey(fromJson: GeofenceModel._dateTimeFromTimestamp, toJson: GeofenceModel._dateTimeToTimestamp)
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final bool notificationSent;

  GeofenceEvent({
    required this.id,
    required this.geofenceId,
    required this.geofenceName,
    required this.userId,
    required this.userName,
    required this.eventType,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.notificationSent = false,
  });

  factory GeofenceEvent.fromJson(Map<String, dynamic> json) =>
      _$GeofenceEventFromJson(json);

  Map<String, dynamic> toJson() => _$GeofenceEventToJson(this);

  factory GeofenceEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GeofenceEvent.fromJson({...data, 'id': doc.id});
  }

  String get formattedMessage {
    final action = eventType == GeofenceEventType.entry ? 'arrived at' : 'left';
    return '$userName $action $geofenceName';
  }

  static GeofenceEventType _eventTypeFromString(String type) {
    return GeofenceEventType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => GeofenceEventType.entry,
    );
  }

  static String _eventTypeToString(GeofenceEventType type) => type.name;
}

enum GeofenceEventType { entry, exit, dwell }
