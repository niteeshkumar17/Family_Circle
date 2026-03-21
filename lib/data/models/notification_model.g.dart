// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NotificationModel _$NotificationModelFromJson(Map<String, dynamic> json) =>
    NotificationModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      type: NotificationModel._typeFromString(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      data: json['data'] as Map<String, dynamic>?,
      createdAt: NotificationModel._dateTimeFromTimestamp(json['createdAt']),
      isRead: json['isRead'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
      priority: json['priority'] == null
          ? NotificationPriority.normal
          : NotificationModel._priorityFromString(json['priority'] as String),
    );

Map<String, dynamic> _$NotificationModelToJson(NotificationModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'type': NotificationModel._typeToString(instance.type),
      'title': instance.title,
      'body': instance.body,
      'data': instance.data,
      'createdAt': NotificationModel._dateTimeToTimestamp(instance.createdAt),
      'isRead': instance.isRead,
      'imageUrl': instance.imageUrl,
      'priority': NotificationModel._priorityToString(instance.priority),
    };
