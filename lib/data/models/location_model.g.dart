// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocationModel _$LocationModelFromJson(Map<String, dynamic> json) =>
    LocationModel(
      id: json['id'] as String?,
      userId: json['userId'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      address: json['address'] as String?,
      batteryLevel: (json['batteryLevel'] as num?)?.toInt() ?? 100,
      isCharging: json['isCharging'] as bool? ?? false,
      networkStatus: json['networkStatus'] as String? ?? 'unknown',
      timestamp: LocationModel._dateTimeFromTimestamp(json['timestamp']),
      source: json['source'] == null
          ? LocationSource.fused
          : LocationModel._sourceFromString(json['source'] as String?),
      isActive: json['isActive'] as bool? ?? true,
    );

Map<String, dynamic> _$LocationModelToJson(LocationModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'accuracy': instance.accuracy,
      'altitude': instance.altitude,
      'speed': instance.speed,
      'heading': instance.heading,
      'address': instance.address,
      'batteryLevel': instance.batteryLevel,
      'isCharging': instance.isCharging,
      'networkStatus': instance.networkStatus,
      'timestamp': LocationModel._dateTimeToTimestamp(instance.timestamp),
      'source': LocationModel._sourceToString(instance.source),
      'isActive': instance.isActive,
    };

LocationHistoryModel _$LocationHistoryModelFromJson(
        Map<String, dynamic> json) =>
    LocationHistoryModel(
      userId: json['userId'] as String,
      date: LocationModel._dateTimeFromTimestamp(json['date']),
      points: (json['points'] as List<dynamic>?)
              ?.map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      totalDistance: (json['totalDistance'] as num?)?.toDouble() ?? 0,
      placeVisits: (json['placeVisits'] as List<dynamic>?)
              ?.map((e) => PlaceVisit.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$LocationHistoryModelToJson(
        LocationHistoryModel instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'date': LocationModel._dateTimeToTimestamp(instance.date),
      'points': instance.points.map((e) => e.toJson()).toList(),
      'totalDistance': instance.totalDistance,
      'placeVisits': instance.placeVisits.map((e) => e.toJson()).toList(),
    };

LocationPoint _$LocationPointFromJson(Map<String, dynamic> json) =>
    LocationPoint(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      time: LocationModel._dateTimeFromTimestamp(json['time']),
    );

Map<String, dynamic> _$LocationPointToJson(LocationPoint instance) =>
    <String, dynamic>{
      'lat': instance.lat,
      'lng': instance.lng,
      'time': LocationModel._dateTimeToTimestamp(instance.time),
    };

PlaceVisit _$PlaceVisitFromJson(Map<String, dynamic> json) => PlaceVisit(
      placeId: json['placeId'] as String?,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      arrivalTime: LocationModel._dateTimeFromTimestamp(json['arrivalTime']),
      departureTime:
          PlaceVisit._nullableDateTimeFromTimestamp(json['departureTime']),
    );

Map<String, dynamic> _$PlaceVisitToJson(PlaceVisit instance) =>
    <String, dynamic>{
      'placeId': instance.placeId,
      'name': instance.name,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'arrivalTime': LocationModel._dateTimeToTimestamp(instance.arrivalTime),
      'departureTime':
          PlaceVisit._nullableDateTimeToTimestamp(instance.departureTime),
    };
