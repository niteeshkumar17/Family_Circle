import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

part 'notification_model.g.dart';

@JsonSerializable(explicitToJson: true)
class NotificationModel {
  final String id;
  final String userId;
  @JsonKey(fromJson: _typeFromString, toJson: _typeToString)
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime createdAt;
  final bool isRead;
  final String? imageUrl;
  @JsonKey(fromJson: _priorityFromString, toJson: _priorityToString)
  final NotificationPriority priority;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    required this.createdAt,
    this.isRead = false,
    this.imageUrl,
    this.priority = NotificationPriority.normal,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      _$NotificationModelFromJson(json);

  Map<String, dynamic> toJson() => _$NotificationModelToJson(this);

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel.fromJson({...data, 'id': doc.id});
  }

  NotificationModel copyWith({
    String? id,
    String? oderId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? createdAt,
    bool? isRead,
    String? imageUrl,
    NotificationPriority? priority,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: oderId ?? userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      imageUrl: imageUrl ?? this.imageUrl,
      priority: priority ?? this.priority,
    );
  }

  /// Get the appropriate channel for this notification
  String get channelId {
    switch (type) {
      case NotificationType.sos:
        return 'sos_alerts';
      case NotificationType.geofenceEntry:
      case NotificationType.geofenceExit:
        return 'geofence_alerts';
      case NotificationType.lowBattery:
      case NotificationType.phoneOff:
        return 'system_alerts';
      case NotificationType.familyJoin:
      case NotificationType.familyLeave:
        return 'family_updates';
      case NotificationType.locationRequest:
      case NotificationType.general:
        return 'general';
    }
  }

  /// Get time ago string
  String get timeAgo {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  static DateTime _dateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now();
  }

  static dynamic _dateTimeToTimestamp(DateTime dateTime) {
    return Timestamp.fromDate(dateTime);
  }

  static NotificationType _typeFromString(String type) {
    return NotificationType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => NotificationType.general,
    );
  }

  static String _typeToString(NotificationType type) => type.name;

  static NotificationPriority _priorityFromString(String priority) {
    return NotificationPriority.values.firstWhere(
      (e) => e.name == priority,
      orElse: () => NotificationPriority.normal,
    );
  }

  static String _priorityToString(NotificationPriority priority) => priority.name;
}

enum NotificationType {
  sos,             // Emergency SOS alert
  geofenceEntry,   // Member entered a geofence
  geofenceExit,    // Member exited a geofence
  lowBattery,      // Member's battery is low
  phoneOff,        // Member's phone went offline
  familyJoin,      // New member joined family
  familyLeave,     // Member left family
  locationRequest, // Someone requested location
  general,         // General notification
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent, // For SOS
}

/// FCM Payload Builder
class FCMPayload {
  static Map<String, dynamic> buildSOSNotification({
    required String eventId,
    required String userId,
    required String userName,
    required double latitude,
    required double longitude,
  }) {
    return {
      'notification': {
        'title': '🚨 SOS EMERGENCY',
        'body': '$userName needs help!',
      },
      'data': {
        'type': NotificationType.sos.name,
        'eventId': eventId,
        'userId': userId,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'android': {
        'priority': 'high',
        'notification': {
          'channel_id': 'sos_alerts',
          'priority': 'max',
          'sound': 'sos_alarm',
          'default_vibrate_timings': false,
          'vibrate_timings': ['0s', '0.5s', '0.25s', '0.5s', '0.25s', '0.5s'],
        },
      },
      'apns': {
        'payload': {
          'aps': {
            'sound': 'sos_alarm.wav',
            'badge': 1,
            'content-available': 1,
          },
        },
      },
    };
  }

  static Map<String, dynamic> buildGeofenceNotification({
    required String userId,
    required String userName,
    required String geofenceName,
    required bool isEntry,
  }) {
    final action = isEntry ? 'arrived at' : 'left';
    return {
      'notification': {
        'title': isEntry ? '📍 Arrival' : '🚶 Departure',
        'body': '$userName $action $geofenceName',
      },
      'data': {
        'type': isEntry 
            ? NotificationType.geofenceEntry.name 
            : NotificationType.geofenceExit.name,
        'userId': userId,
        'geofenceName': geofenceName,
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'android': {
        'notification': {
          'channel_id': 'geofence_alerts',
        },
      },
    };
  }

  static Map<String, dynamic> buildLowBatteryNotification({
    required String userId,
    required String userName,
    required int batteryLevel,
  }) {
    return {
      'notification': {
        'title': '🔋 Low Battery Alert',
        'body': '$userName\'s phone is at $batteryLevel%',
      },
      'data': {
        'type': NotificationType.lowBattery.name,
        'userId': userId,
        'batteryLevel': batteryLevel.toString(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'android': {
        'notification': {
          'channel_id': 'system_alerts',
        },
      },
    };
  }
}
