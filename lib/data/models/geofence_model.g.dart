// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geofence_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GeofenceModel _$GeofenceModelFromJson(Map<String, dynamic> json) =>
    GeofenceModel(
      id: json['id'] as String,
      familyId: json['familyId'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      type: GeofenceModel._typeFromString(json['type'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200,
      address: json['address'] as String?,
      createdBy: json['createdBy'] as String,
      createdAt: GeofenceModel._dateTimeFromTimestamp(json['createdAt']),
      isActive: json['isActive'] as bool? ?? true,
      settings:
          GeofenceSettings.fromJson(json['settings'] as Map<String, dynamic>),
      monitoredMembers: (json['monitoredMembers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$GeofenceModelToJson(GeofenceModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'familyId': instance.familyId,
      'name': instance.name,
      'icon': instance.icon,
      'type': GeofenceModel._typeToString(instance.type),
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'radiusMeters': instance.radiusMeters,
      'address': instance.address,
      'createdBy': instance.createdBy,
      'createdAt': GeofenceModel._dateTimeToTimestamp(instance.createdAt),
      'isActive': instance.isActive,
      'settings': instance.settings.toJson(),
      'monitoredMembers': instance.monitoredMembers,
    };

GeofenceSettings _$GeofenceSettingsFromJson(Map<String, dynamic> json) =>
    GeofenceSettings(
      notifyOnEntry: json['notifyOnEntry'] as bool? ?? true,
      notifyOnExit: json['notifyOnExit'] as bool? ?? true,
      notifyMembers: (json['notifyMembers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      enableQuietHours: json['enableQuietHours'] as bool? ?? false,
      quietStart: GeofenceSettings._timeOfDayFromJson(
          json['quietStart'] as Map<String, dynamic>?),
      quietEnd: GeofenceSettings._timeOfDayFromJson(
          json['quietEnd'] as Map<String, dynamic>?),
    );

Map<String, dynamic> _$GeofenceSettingsToJson(GeofenceSettings instance) =>
    <String, dynamic>{
      'notifyOnEntry': instance.notifyOnEntry,
      'notifyOnExit': instance.notifyOnExit,
      'notifyMembers': instance.notifyMembers,
      'enableQuietHours': instance.enableQuietHours,
      'quietStart': GeofenceSettings._timeOfDayToJson(instance.quietStart),
      'quietEnd': GeofenceSettings._timeOfDayToJson(instance.quietEnd),
    };

GeofenceEvent _$GeofenceEventFromJson(Map<String, dynamic> json) =>
    GeofenceEvent(
      id: json['id'] as String,
      geofenceId: json['geofenceId'] as String,
      geofenceName: json['geofenceName'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      eventType:
          GeofenceEvent._eventTypeFromString(json['eventType'] as String),
      timestamp: GeofenceModel._dateTimeFromTimestamp(json['timestamp']),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      notificationSent: json['notificationSent'] as bool? ?? false,
    );

Map<String, dynamic> _$GeofenceEventToJson(GeofenceEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'geofenceId': instance.geofenceId,
      'geofenceName': instance.geofenceName,
      'userId': instance.userId,
      'userName': instance.userName,
      'eventType': GeofenceEvent._eventTypeToString(instance.eventType),
      'timestamp': GeofenceModel._dateTimeToTimestamp(instance.timestamp),
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'notificationSent': instance.notificationSent,
    };
