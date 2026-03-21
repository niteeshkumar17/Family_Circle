// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserModel _$UserModelFromJson(Map<String, dynamic> json) => UserModel(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      email: json['email'] as String?,
      createdAt: UserModel._dateTimeFromTimestamp(json['createdAt']),
      lastActive: UserModel._dateTimeFromTimestamp(json['lastActive']),
      settings: UserSettings.fromJson(json['settings'] as Map<String, dynamic>),
      familyIds: (json['familyIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      currentFamilyId: json['currentFamilyId'] as String?,
      deviceInfo: json['deviceInfo'] == null
          ? null
          : DeviceInfo.fromJson(json['deviceInfo'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$UserModelToJson(UserModel instance) => <String, dynamic>{
      'id': instance.id,
      'phoneNumber': instance.phoneNumber,
      'displayName': instance.displayName,
      'photoUrl': instance.photoUrl,
      'email': instance.email,
      'createdAt': UserModel._dateTimeToTimestamp(instance.createdAt),
      'lastActive': UserModel._dateTimeToTimestamp(instance.lastActive),
      'settings': instance.settings.toJson(),
      'familyIds': instance.familyIds,
      'currentFamilyId': instance.currentFamilyId,
      'deviceInfo': instance.deviceInfo?.toJson(),
    };

UserSettings _$UserSettingsFromJson(Map<String, dynamic> json) => UserSettings(
      locationSharingEnabled: json['locationSharingEnabled'] as bool? ?? true,
      locationUpdateInterval:
          (json['locationUpdateInterval'] as num?)?.toInt() ?? 15,
      sosAlertsEnabled: json['sosAlertsEnabled'] as bool? ?? true,
      geofenceAlertsEnabled: json['geofenceAlertsEnabled'] as bool? ?? true,
      lowBatteryAlertsEnabled: json['lowBatteryAlertsEnabled'] as bool? ?? true,
      quietHoursEnabled: json['quietHoursEnabled'] as bool? ?? false,
      quietHoursStart: UserSettings._timeOfDayFromJson(
          json['quietHoursStart'] as Map<String, dynamic>?),
      quietHoursEnd: UserSettings._timeOfDayFromJson(
          json['quietHoursEnd'] as Map<String, dynamic>?),
    );

Map<String, dynamic> _$UserSettingsToJson(UserSettings instance) =>
    <String, dynamic>{
      'locationSharingEnabled': instance.locationSharingEnabled,
      'locationUpdateInterval': instance.locationUpdateInterval,
      'sosAlertsEnabled': instance.sosAlertsEnabled,
      'geofenceAlertsEnabled': instance.geofenceAlertsEnabled,
      'lowBatteryAlertsEnabled': instance.lowBatteryAlertsEnabled,
      'quietHoursEnabled': instance.quietHoursEnabled,
      'quietHoursStart':
          UserSettings._timeOfDayToJson(instance.quietHoursStart),
      'quietHoursEnd': UserSettings._timeOfDayToJson(instance.quietHoursEnd),
    };

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
      deviceId: json['deviceId'] as String,
      platform: json['platform'] as String,
      osVersion: json['osVersion'] as String,
      appVersion: json['appVersion'] as String,
      fcmToken: json['fcmToken'] as String?,
    );

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'platform': instance.platform,
      'osVersion': instance.osVersion,
      'appVersion': instance.appVersion,
      'fcmToken': instance.fcmToken,
    };
