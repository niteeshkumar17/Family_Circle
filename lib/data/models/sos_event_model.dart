import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';
import 'location_model.dart';

part 'sos_event_model.g.dart';

@JsonSerializable(explicitToJson: true)
class SOSEventModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String familyId;
  @JsonKey(fromJson: _statusFromString, toJson: _statusToString)
  final SOSStatus status;
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime triggeredAt;
  @JsonKey(fromJson: _nullableDateTimeFromTimestamp, toJson: _nullableDateTimeToTimestamp)
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final LocationModel triggerLocation;
  final List<LocationModel> trackingHistory;
  final List<SOSResponse> responses;
  final String? notes;
  final String? emergencyContact;

  SOSEventModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.familyId,
    this.status = SOSStatus.active,
    required this.triggeredAt,
    this.resolvedAt,
    this.resolvedBy,
    required this.triggerLocation,
    this.trackingHistory = const [],
    this.responses = const [],
    this.notes,
    this.emergencyContact,
  });

  factory SOSEventModel.fromJson(Map<String, dynamic> json) =>
      _$SOSEventModelFromJson(json);

  Map<String, dynamic> toJson() => _$SOSEventModelToJson(this);

  factory SOSEventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SOSEventModel.fromJson({...data, 'id': doc.id});
  }

  SOSEventModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    String? familyId,
    SOSStatus? status,
    DateTime? triggeredAt,
    DateTime? resolvedAt,
    String? resolvedBy,
    LocationModel? triggerLocation,
    List<LocationModel>? trackingHistory,
    List<SOSResponse>? responses,
    String? notes,
    String? emergencyContact,
  }) {
    return SOSEventModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      familyId: familyId ?? this.familyId,
      status: status ?? this.status,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      triggerLocation: triggerLocation ?? this.triggerLocation,
      trackingHistory: trackingHistory ?? this.trackingHistory,
      responses: responses ?? this.responses,
      notes: notes ?? this.notes,
      emergencyContact: emergencyContact ?? this.emergencyContact,
    );
  }

  /// Check if SOS is currently active
  bool get isActive => status == SOSStatus.active;

  /// Get duration since SOS was triggered
  Duration get duration {
    final endTime = resolvedAt ?? DateTime.now();
    return endTime.difference(triggeredAt);
  }

  /// Get formatted duration string
  String get formattedDuration {
    final d = duration;
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get latest location from tracking history
  LocationModel get latestLocation {
    if (trackingHistory.isNotEmpty) {
      return trackingHistory.last;
    }
    return triggerLocation;
  }

  /// Get response count for each type
  int getResponseCount(SOSResponseType type) {
    return responses.where((r) => r.responseType == type).length;
  }

  /// Check if a user has responded
  bool hasUserResponded(String userId) {
    return responses.any((r) => r.userId == userId);
  }

  static DateTime _dateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now();
  }

  static dynamic _dateTimeToTimestamp(DateTime dateTime) {
    return Timestamp.fromDate(dateTime);
  }

  static DateTime? _nullableDateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    return _dateTimeFromTimestamp(timestamp);
  }

  static dynamic _nullableDateTimeToTimestamp(DateTime? dateTime) {
    if (dateTime == null) return null;
    return _dateTimeToTimestamp(dateTime);
  }

  static SOSStatus _statusFromString(String status) {
    return SOSStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => SOSStatus.active,
    );
  }

  static String _statusToString(SOSStatus status) => status.name;
}

enum SOSStatus { 
  active,      // SOS is active, tracking in progress
  responded,   // At least one family member has responded
  resolved,    // SOS has been resolved/closed
  cancelled,   // User cancelled the SOS
}

@JsonSerializable()
class SOSResponse {
  final String id;
  final String userId;
  final String userName;
  @JsonKey(fromJson: SOSEventModel._dateTimeFromTimestamp, toJson: SOSEventModel._dateTimeToTimestamp)
  final DateTime timestamp;
  @JsonKey(fromJson: _responseTypeFromString, toJson: _responseTypeToString)
  final SOSResponseType responseType;
  final String? message;
  final double? responderLatitude;
  final double? responderLongitude;

  SOSResponse({
    required this.id,
    required this.userId,
    required this.userName,
    required this.timestamp,
    required this.responseType,
    this.message,
    this.responderLatitude,
    this.responderLongitude,
  });

  factory SOSResponse.fromJson(Map<String, dynamic> json) =>
      _$SOSResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SOSResponseToJson(this);

  String get formattedMessage {
    switch (responseType) {
      case SOSResponseType.acknowledged:
        return '$userName saw the alert';
      case SOSResponseType.onTheWay:
        return '$userName is on the way';
      case SOSResponseType.called:
        return '$userName called';
      case SOSResponseType.resolved:
        return '$userName marked as resolved';
      case SOSResponseType.message:
        return '$userName: ${message ?? ""}';
    }
  }

  static SOSResponseType _responseTypeFromString(String type) {
    return SOSResponseType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => SOSResponseType.acknowledged,
    );
  }

  static String _responseTypeToString(SOSResponseType type) => type.name;
}

enum SOSResponseType {
  acknowledged, // User acknowledged the alert
  onTheWay,     // User is coming to help
  called,       // User called the SOS sender
  resolved,     // User marked SOS as resolved
  message,      // User sent a message
}

/// Active SOS data for Realtime Database
class ActiveSOSData {
  final String eventId;
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String status;

  ActiveSOSData({
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.status,
  });

  factory ActiveSOSData.fromRealtimeDb(Map<dynamic, dynamic> data) {
    return ActiveSOSData(
      eventId: data['eventId'] as String,
      userId: data['userId'] as String,
      userName: data['userName'] as String,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
      status: data['status'] as String,
    );
  }

  Map<String, dynamic> toRealtimeDb() {
    return {
      'eventId': eventId,
      'userId': userId,
      'userName': userName,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status,
    };
  }
}
