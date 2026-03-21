import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable(explicitToJson: true)
class UserModel {
  final String id;
  final String phoneNumber;
  final String? displayName;
  final String? photoUrl;
  final String? email;
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime createdAt;
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime lastActive;
  final UserSettings settings;
  final List<String> familyIds;
  final String? currentFamilyId;
  final DeviceInfo? deviceInfo;

  UserModel({
    required this.id,
    required this.phoneNumber,
    this.displayName,
    this.photoUrl,
    this.email,
    required this.createdAt,
    required this.lastActive,
    required this.settings,
    this.familyIds = const [],
    this.currentFamilyId,
    this.deviceInfo,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromJson({...data, 'id': doc.id});
  }

  UserModel copyWith({
    String? id,
    String? phoneNumber,
    String? displayName,
    String? photoUrl,
    String? email,
    DateTime? createdAt,
    DateTime? lastActive,
    UserSettings? settings,
    List<String>? familyIds,
    String? currentFamilyId,
    DeviceInfo? deviceInfo,
  }) {
    return UserModel(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
      settings: settings ?? this.settings,
      familyIds: familyIds ?? this.familyIds,
      currentFamilyId: currentFamilyId ?? this.currentFamilyId,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
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
}

@JsonSerializable()
class UserSettings {
  final bool locationSharingEnabled;
  final int locationUpdateInterval; // seconds
  final bool sosAlertsEnabled;
  final bool geofenceAlertsEnabled;
  final bool lowBatteryAlertsEnabled;
  final bool quietHoursEnabled;
  @JsonKey(fromJson: _timeOfDayFromJson, toJson: _timeOfDayToJson)
  final TimeOfDay? quietHoursStart;
  @JsonKey(fromJson: _timeOfDayFromJson, toJson: _timeOfDayToJson)
  final TimeOfDay? quietHoursEnd;

  UserSettings({
    this.locationSharingEnabled = true,
    this.locationUpdateInterval = 15,
    this.sosAlertsEnabled = true,
    this.geofenceAlertsEnabled = true,
    this.lowBatteryAlertsEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) =>
      _$UserSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$UserSettingsToJson(this);

  UserSettings copyWith({
    bool? locationSharingEnabled,
    int? locationUpdateInterval,
    bool? sosAlertsEnabled,
    bool? geofenceAlertsEnabled,
    bool? lowBatteryAlertsEnabled,
    bool? quietHoursEnabled,
    TimeOfDay? quietHoursStart,
    TimeOfDay? quietHoursEnd,
  }) {
    return UserSettings(
      locationSharingEnabled: locationSharingEnabled ?? this.locationSharingEnabled,
      locationUpdateInterval: locationUpdateInterval ?? this.locationUpdateInterval,
      sosAlertsEnabled: sosAlertsEnabled ?? this.sosAlertsEnabled,
      geofenceAlertsEnabled: geofenceAlertsEnabled ?? this.geofenceAlertsEnabled,
      lowBatteryAlertsEnabled: lowBatteryAlertsEnabled ?? this.lowBatteryAlertsEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    );
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

@JsonSerializable()
class DeviceInfo {
  final String deviceId;
  final String platform;
  final String osVersion;
  final String appVersion;
  final String? fcmToken;

  DeviceInfo({
    required this.deviceId,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    this.fcmToken,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);

  DeviceInfo copyWith({
    String? deviceId,
    String? platform,
    String? osVersion,
    String? appVersion,
    String? fcmToken,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      platform: platform ?? this.platform,
      osVersion: osVersion ?? this.osVersion,
      appVersion: appVersion ?? this.appVersion,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
