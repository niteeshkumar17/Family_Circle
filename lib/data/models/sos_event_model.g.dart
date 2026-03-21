// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sos_event_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SOSEventModel _$SOSEventModelFromJson(Map<String, dynamic> json) =>
    SOSEventModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      userPhotoUrl: json['userPhotoUrl'] as String?,
      familyId: json['familyId'] as String,
      status: json['status'] == null
          ? SOSStatus.active
          : SOSEventModel._statusFromString(json['status'] as String),
      triggeredAt: SOSEventModel._dateTimeFromTimestamp(json['triggeredAt']),
      resolvedAt:
          SOSEventModel._nullableDateTimeFromTimestamp(json['resolvedAt']),
      resolvedBy: json['resolvedBy'] as String?,
      triggerLocation: LocationModel.fromJson(
          json['triggerLocation'] as Map<String, dynamic>),
      trackingHistory: (json['trackingHistory'] as List<dynamic>?)
              ?.map((e) => LocationModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      responses: (json['responses'] as List<dynamic>?)
              ?.map((e) => SOSResponse.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      notes: json['notes'] as String?,
      emergencyContact: json['emergencyContact'] as String?,
    );

Map<String, dynamic> _$SOSEventModelToJson(SOSEventModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'userName': instance.userName,
      'userPhotoUrl': instance.userPhotoUrl,
      'familyId': instance.familyId,
      'status': SOSEventModel._statusToString(instance.status),
      'triggeredAt': SOSEventModel._dateTimeToTimestamp(instance.triggeredAt),
      'resolvedAt':
          SOSEventModel._nullableDateTimeToTimestamp(instance.resolvedAt),
      'resolvedBy': instance.resolvedBy,
      'triggerLocation': instance.triggerLocation.toJson(),
      'trackingHistory':
          instance.trackingHistory.map((e) => e.toJson()).toList(),
      'responses': instance.responses.map((e) => e.toJson()).toList(),
      'notes': instance.notes,
      'emergencyContact': instance.emergencyContact,
    };

SOSResponse _$SOSResponseFromJson(Map<String, dynamic> json) => SOSResponse(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      timestamp: SOSEventModel._dateTimeFromTimestamp(json['timestamp']),
      responseType:
          SOSResponse._responseTypeFromString(json['responseType'] as String),
      message: json['message'] as String?,
      responderLatitude: (json['responderLatitude'] as num?)?.toDouble(),
      responderLongitude: (json['responderLongitude'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$SOSResponseToJson(SOSResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'userName': instance.userName,
      'timestamp': SOSEventModel._dateTimeToTimestamp(instance.timestamp),
      'responseType': SOSResponse._responseTypeToString(instance.responseType),
      'message': instance.message,
      'responderLatitude': instance.responderLatitude,
      'responderLongitude': instance.responderLongitude,
    };
