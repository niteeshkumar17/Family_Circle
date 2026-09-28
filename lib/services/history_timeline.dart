import 'dart:math' as math;

import '../config/app_config.dart';

/// One stored breadcrumb from `locationHistory/{familyId}/{userId}/{day}`.
class HistoryPoint {
  final double latitude;
  final double longitude;
  final double? accuracy;

  /// Metres per second as reported by the GPS, when it reported one.
  final double? speed;
  final DateTime time;
  final String? address;

  const HistoryPoint({
    required this.latitude,
    required this.longitude,
    required this.time,
    this.accuracy,
    this.speed,
    this.address,
  });

  static HistoryPoint? fromMap(Map<String, dynamic> map) {
    final lat = (map['latitude'] as num?)?.toDouble();
    final lng = (map['longitude'] as num?)?.toDouble();
    final ts = (map['timestamp'] as num?)?.toInt();
    if (lat == null || lng == null || ts == null) return null;
    final address = map['address'];
    return HistoryPoint(
      latitude: lat,
      longitude: lng,
      time: DateTime.fromMillisecondsSinceEpoch(ts),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      address: address is String && address.trim().isNotEmpty ? address : null,
    );
  }
}

/// A saved place (geofence) that stops can be labelled with.
class KnownPlace {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const KnownPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });
}

sealed class TimelineEntry {
  final DateTime start;
  final DateTime end;

  const TimelineEntry({required this.start, required this.end});

  Duration get duration => end.difference(start);
}

/// Time spent in one spot.
class StayEntry extends TimelineEntry {
  final double latitude;
  final double longitude;
  final KnownPlace? place;
  final String? address;
  final List<HistoryPoint> points;

  /// The member was already here before the selected day began.
  final bool startedEarlier;

  /// Still here: the last entry of today with no movement recorded since.
  final bool ongoing;

  const StayEntry({
    required super.start,
    required super.end,
    required this.latitude,
    required this.longitude,
    required this.points,
    this.place,
    this.address,
    this.startedEarlier = false,
    this.ongoing = false,
  });

  String get label => place?.name ?? address ?? 'Unnamed place';
}

enum TripMode { walking, driving, unknown }

/// Movement between two stays.
class TripEntry extends TimelineEntry {
  /// Ordered path including the stay centres it leaves from and arrives at.
  final List<HistoryPoint> path;
  final double distanceMeters;
  final double? topSpeedMps;

  /// Indices `i` whose segment `path[i] -> path[i + 1]` was not recorded: the
  /// device went silent, so the true route between them is unknown.
  final Set<int> gapSegments;

  const TripEntry({
    required super.start,
    required super.end,
    required this.path,
    required this.distanceMeters,
    required this.gapSegments,
    this.topSpeedMps,
  });

  bool get hasGap => gapSegments.isNotEmpty;

  TripMode get mode {
    final seconds = duration.inSeconds;
    final average = seconds >= 60 ? distanceMeters / seconds : null;
    final top = topSpeedMps ?? 0;
    // 25 km/h top speed or a 14 km/h average is beyond anyone on foot.
    if (top > 7 || (average != null && average > 4)) return TripMode.driving;
    if (average != null && average > 0.4) return TripMode.walking;
    if (average == null && distanceMeters > 3000) return TripMode.driving;
    return TripMode.unknown;
  }
}

class DayTimeline {
  final List<TimelineEntry> entries;

  /// Breadcrumbs that survived cleaning, in time order.
  final List<HistoryPoint> points;

  const DayTimeline({required this.entries, required this.points});

  static const empty = DayTimeline(entries: [], points: []);

  bool get isEmpty => entries.isEmpty;

  Iterable<TripEntry> get trips => entries.whereType<TripEntry>();
  Iterable<StayEntry> get stays => entries.whereType<StayEntry>();

  double get totalDistanceMeters =>
      trips.fold(0.0, (sum, trip) => sum + trip.distanceMeters);

  Duration get movingTime =>
      trips.fold(Duration.zero, (sum, trip) => sum + trip.duration);
}

/// Reconstructs a day of stops and trips from raw breadcrumbs.
///
/// Drawing the raw points as one line made every indoor GPS wobble look like a
/// journey and joined gaps with straight lines across the city. This follows
/// the approach consumer timelines use: drop imprecise and physically
/// impossible fixes, group consecutive fixes that stay near one centre into a
/// stop, and treat whatever lies between two stops as a trip.
class HistoryTimelineBuilder {
  /// Anything faster than this between two fixes is a glitch, not travel.
  static const double _maxPlausibleSpeedMps = 70;

  /// About 30 km/h: faster than anyone slows to while parking.
  static const double _drivingSpeedMps = 8;

  static DayTimeline build({
    required List<HistoryPoint> points,
    HistoryPoint? previousDayLast,
    List<KnownPlace> places = const [],
    bool isToday = false,
    DateTime? now,
    double stayRadiusMeters = AppConfig.stayRadiusMeters,
    Duration minStay = const Duration(seconds: AppConfig.stayMinSeconds),
    Duration gapThreshold =
        const Duration(seconds: AppConfig.historyGapSeconds),
    double maxAccuracyMeters = AppConfig.historyMaxAccuracyMeters,
  }) {
    final clean = _clean(points, maxAccuracyMeters);
    if (clean.isEmpty) return DayTimeline.empty;

    final clusters = _cluster(clean, stayRadiusMeters);

    // A stop lasts until the next fix: while resting, the tracker records the
    // arrival and then stays quiet until the phone moves again, so the next
    // fix is the best estimate of when the member left.
    final isStay = List<bool>.generate(clusters.length, (i) {
      final cluster = clusters[i];
      final isLast = i == clusters.length - 1;

      // A lone fix taken at driving speed is traffic, not a destination, even
      // if silence follows it: that is the phone dying or losing signal
      // mid-journey, and it should read as a gap in the route.
      if (clusters.length > 1 &&
          cluster.points.length == 1 &&
          (cluster.first.speed ?? 0) > _drivingSpeedMps) {
        return false;
      }

      final departure =
          isLast ? cluster.last.time : clusters[i + 1].first.time;
      if (departure.difference(cluster.first.time) >= minStay) return true;
      // The day ended here: wherever the last fix was is where they stayed.
      if (isLast) return true;
      // Already here overnight.
      if (i == 0 && previousDayLast != null) {
        return _distance(cluster.centroidLat, cluster.centroidLng,
                previousDayLast.latitude, previousDayLast.longitude) <=
            stayRadiusMeters;
      }
      return false;
    });

    final entries = <TimelineEntry>[];
    final pendingTrip = <HistoryPoint>[];
    StayEntry? previousStay;

    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      if (!isStay[i]) {
        pendingTrip.addAll(cluster.points);
        continue;
      }

      final departure = i + 1 < clusters.length
          ? clusters[i + 1].first.time
          : cluster.last.time;

      final startedEarlier = i == 0 &&
          previousDayLast != null &&
          _distance(cluster.centroidLat, cluster.centroidLng,
                  previousDayLast.latitude, previousDayLast.longitude) <=
              stayRadiusMeters;

      final isLast = i == clusters.length - 1;
      final ongoing = isLast && isToday;
      final current = now ?? DateTime.now();

      final stay = StayEntry(
        start: startedEarlier ? previousDayLast.time : cluster.first.time,
        end: ongoing && current.isAfter(departure) ? current : departure,
        latitude: cluster.centroidLat,
        longitude: cluster.centroidLng,
        points: List.unmodifiable(cluster.points),
        place: _matchPlace(cluster.centroidLat, cluster.centroidLng, places),
        address: _bestAddress(cluster.points),
        startedEarlier: startedEarlier,
        ongoing: ongoing,
      );

      if (pendingTrip.isNotEmpty || previousStay != null) {
        final trip = _buildTrip(
          from: previousStay,
          points: pendingTrip,
          to: stay,
          gapThreshold: gapThreshold,
        );
        if (trip != null) entries.add(trip);
      }
      pendingTrip.clear();

      entries.add(stay);
      previousStay = stay;
    }

    // Still on the move at the last fix: a drive in progress today, or a phone
    // that went quiet mid-journey.
    if (pendingTrip.isNotEmpty) {
      final trip = _buildTrip(
        from: previousStay,
        points: pendingTrip,
        to: null,
        gapThreshold: gapThreshold,
      );
      if (trip != null) entries.add(trip);
    }

    return DayTimeline(
      entries: List.unmodifiable(
          _mergeAdjacentStays(entries, stayRadiusMeters, gapThreshold)),
      points: List.unmodifiable(clean),
    );
  }

  /// Sorts, drops imprecise fixes, duplicates and single-fix teleports.
  static List<HistoryPoint> _clean(
      List<HistoryPoint> raw, double maxAccuracyMeters) {
    final sorted = raw
        .where((p) => p.accuracy == null || p.accuracy! <= maxAccuracyMeters)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final kept = <HistoryPoint>[];
    for (var k = 0; k < sorted.length; k++) {
      final point = sorted[k];
      if (kept.isNotEmpty && !point.time.isAfter(kept.last.time)) continue;

      if (kept.isNotEmpty && _implausible(kept.last, point)) {
        final next = k + 1 < sorted.length ? sorted[k + 1] : null;
        // An out-and-back spike: impossible to reach and impossible to leave,
        // while its neighbours are consistent with each other.
        if (next == null ||
            (_implausible(point, next) && !_implausible(kept.last, next))) {
          continue;
        }
      }
      kept.add(point);
    }
    return kept;
  }

  static bool _implausible(HistoryPoint a, HistoryPoint b) {
    final seconds = b.time.difference(a.time).inMilliseconds / 1000;
    if (seconds <= 0) return true;
    final slack = (a.accuracy ?? 0) + (b.accuracy ?? 0);
    final metres =
        _distance(a.latitude, a.longitude, b.latitude, b.longitude) - slack;
    return metres > 0 && metres / seconds > _maxPlausibleSpeedMps;
  }

  static List<_Cluster> _cluster(List<HistoryPoint> points, double radius) {
    final clusters = <_Cluster>[];
    for (final point in points) {
      final current = clusters.isEmpty ? null : clusters.last;
      if (current != null &&
          _distance(current.centroidLat, current.centroidLng, point.latitude,
                  point.longitude) <=
              radius) {
        current.add(point);
      } else {
        clusters.add(_Cluster(point));
      }
    }
    return clusters;
  }

  static TripEntry? _buildTrip({
    required StayEntry? from,
    required List<HistoryPoint> points,
    required StayEntry? to,
    required Duration gapThreshold,
  }) {
    final path = <HistoryPoint>[
      if (from != null)
        HistoryPoint(
          latitude: from.latitude,
          longitude: from.longitude,
          time: from.end,
        ),
      ...points,
      if (to != null)
        HistoryPoint(
          latitude: to.latitude,
          longitude: to.longitude,
          time: to.start,
        ),
    ];
    if (path.length < 2) return null;

    var distance = 0.0;
    final gaps = <int>{};
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      distance += _distance(a.latitude, a.longitude, b.latitude, b.longitude);
      if (b.time.difference(a.time) > gapThreshold) gaps.add(i);
    }

    double? topSpeed;
    for (final p in points) {
      final s = p.speed;
      if (s != null && s > 0 && s < _maxPlausibleSpeedMps) {
        topSpeed = topSpeed == null ? s : math.max(topSpeed, s);
      }
    }

    return TripEntry(
      start: path.first.time,
      end: path.last.time,
      path: List.unmodifiable(path),
      distanceMeters: distance,
      gapSegments: gaps,
      topSpeedMps: topSpeed,
    );
  }

  /// Joins two stops that are really one: a short wobble outside the radius
  /// used to split a single night at home into several visits.
  static List<TimelineEntry> _mergeAdjacentStays(
    List<TimelineEntry> entries,
    double radius,
    Duration gapThreshold,
  ) {
    final result = <TimelineEntry>[];
    for (final entry in entries) {
      if (entry is StayEntry && result.isNotEmpty) {
        final last = result.last;
        final beforeLast = result.length >= 2 ? result[result.length - 2] : null;

        StayEntry? previous;
        var dropTrip = false;
        if (last is StayEntry) {
          previous = last;
        } else if (last is TripEntry &&
            beforeLast is StayEntry &&
            last.distanceMeters < radius * 4 &&
            !last.hasGap) {
          previous = beforeLast;
          dropTrip = true;
        }

        if (previous != null &&
            _distance(previous.latitude, previous.longitude, entry.latitude,
                    entry.longitude) <=
                radius * 1.5) {
          if (dropTrip) result.removeLast();
          result.removeLast();
          result.add(StayEntry(
            start: previous.start,
            end: entry.end,
            latitude: previous.latitude,
            longitude: previous.longitude,
            points: List.unmodifiable([...previous.points, ...entry.points]),
            place: previous.place ?? entry.place,
            address: previous.address ?? entry.address,
            startedEarlier: previous.startedEarlier,
            ongoing: entry.ongoing,
          ));
          continue;
        }
      }
      result.add(entry);
    }
    return result;
  }

  static KnownPlace? _matchPlace(
      double lat, double lng, List<KnownPlace> places) {
    KnownPlace? best;
    var bestDistance = double.infinity;
    for (final place in places) {
      final d = _distance(lat, lng, place.latitude, place.longitude);
      // A little slack: the stop centre is an average of imprecise fixes.
      if (d <= place.radiusMeters + 50 && d < bestDistance) {
        best = place;
        bestDistance = d;
      }
    }
    return best;
  }

  static String? _bestAddress(List<HistoryPoint> points) {
    final counts = <String, int>{};
    for (final p in points) {
      final a = p.address;
      if (a != null) counts[a] = (counts[a] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static double _distance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _Cluster {
  final List<HistoryPoint> points;
  double _sumLat;
  double _sumLng;

  _Cluster(HistoryPoint first)
      : points = [first],
        _sumLat = first.latitude,
        _sumLng = first.longitude;

  void add(HistoryPoint point) {
    points.add(point);
    _sumLat += point.latitude;
    _sumLng += point.longitude;
  }

  HistoryPoint get first => points.first;
  HistoryPoint get last => points.last;
  double get centroidLat => _sumLat / points.length;
  double get centroidLng => _sumLng / points.length;
}
