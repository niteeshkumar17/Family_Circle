import 'package:family_nest/services/history_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _home = (lat: 28.6700, lng: 77.4500);
const _office = (lat: 28.6280, lng: 77.3700); // ~9 km from home

final _day = DateTime(2026, 9, 1);

DateTime _at(int hour, int minute) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute);

HistoryPoint _p(
  ({double lat, double lng}) where,
  DateTime time, {
  double accuracy = 15,
  double? speed,
  String? address,
}) =>
    HistoryPoint(
      latitude: where.lat,
      longitude: where.lng,
      time: time,
      accuracy: accuracy,
      speed: speed,
      address: address,
    );

/// Fixes every minute along a straight line, excluding both ends.
List<HistoryPoint> _drive(
  ({double lat, double lng}) from,
  ({double lat, double lng}) to,
  DateTime start, {
  int steps = 20,
  double speed = 12,
}) {
  return [
    for (var i = 1; i < steps; i++)
      _p(
        (
          lat: from.lat + (to.lat - from.lat) * i / steps,
          lng: from.lng + (to.lng - from.lng) * i / steps,
        ),
        start.add(Duration(minutes: i)),
        speed: speed,
      ),
  ];
}

void main() {
  test('a commute day becomes home, drive, office, drive, home', () {
    final points = [
      _p(_home, _at(8, 0), address: 'Home Street'),
      ..._drive(_home, _office, _at(8, 30)),
      _p(_office, _at(8, 52), address: 'Office Park'),
      ..._drive(_office, _home, _at(18, 5)),
      _p(_home, _at(18, 40), address: 'Home Street'),
    ];

    final timeline = HistoryTimelineBuilder.build(
      points: points,
      previousDayLast:
          _p(_home, DateTime(2026, 8, 31, 23, 4), address: 'Home Street'),
      places: const [
        KnownPlace(
          id: 'h',
          name: 'Home',
          latitude: 28.6700,
          longitude: 77.4500,
          radiusMeters: 150,
        ),
      ],
    );

    expect(
      timeline.entries.map((e) => e.runtimeType).toList(),
      [StayEntry, TripEntry, StayEntry, TripEntry, StayEntry],
    );

    final morning = timeline.entries[0] as StayEntry;
    expect(morning.label, 'Home');
    expect(morning.startedEarlier, isTrue);
    expect(morning.start, DateTime(2026, 8, 31, 23, 4));

    final office = timeline.entries[2] as StayEntry;
    expect(office.label, 'Office Park');
    expect(office.start, _at(8, 52));
    // Lasts until the first fix of the drive home.
    expect(office.end, _at(18, 6));

    final commute = timeline.entries[1] as TripEntry;
    expect(commute.mode, TripMode.driving);
    expect(commute.hasGap, isFalse);
    expect(commute.distanceMeters, inInclusiveRange(8000, 11000));

    expect(timeline.totalDistanceMeters, inInclusiveRange(16000, 22000));
  });

  test('indoor wobble and imprecise fixes do not create trips', () {
    final points = [
      for (var m = 0; m < 120; m += 10)
        _p(
          (lat: _home.lat + (m.isEven ? 0.0004 : -0.0004), lng: _home.lng),
          _at(22, 0).add(Duration(minutes: m)),
        ),
      // A cell-tower fix two kilometres off.
      _p((lat: _home.lat + 0.02, lng: _home.lng), _at(23, 5), accuracy: 900),
    ];

    final timeline = HistoryTimelineBuilder.build(points: points);

    expect(timeline.stays, hasLength(1));
    expect(timeline.trips, isEmpty);
    expect(timeline.totalDistanceMeters, 0);
  });

  test('a single impossible jump is discarded', () {
    final points = [
      _p(_home, _at(10, 0)),
      _p(_home, _at(10, 10)),
      // 50 km away one minute later, then back: a glitch, not a trip.
      _p((lat: _home.lat + 0.45, lng: _home.lng), _at(10, 11)),
      _p(_home, _at(10, 12)),
      _p(_home, _at(10, 30)),
    ];

    final timeline = HistoryTimelineBuilder.build(points: points);

    expect(timeline.points, hasLength(4));
    expect(timeline.trips, isEmpty);
  });

  test('silence mid-drive is a gap in the route, not a stop', () {
    final midway = (
      lat: (_home.lat + _office.lat) / 2,
      lng: (_home.lng + _office.lng) / 2,
    );
    final points = [
      _p(_home, _at(9, 0)),
      ..._drive(_home, midway, _at(9, 20), steps: 10, speed: 15),
      // Phone loses signal for an hour at highway speed, then resumes.
      ..._drive(midway, _office, _at(10, 30), steps: 10, speed: 15),
      _p(_office, _at(10, 45)),
    ];

    final timeline = HistoryTimelineBuilder.build(points: points);

    expect(timeline.stays, hasLength(2));
    final trip = timeline.trips.single;
    expect(trip.hasGap, isTrue);
  });

  test('today ends with an ongoing stay', () {
    final now = _at(21, 0);
    final timeline = HistoryTimelineBuilder.build(
      points: [
        _p(_office, _at(9, 0)),
        ..._drive(_office, _home, _at(18, 0)),
        _p(_home, _at(18, 30)),
      ],
      isToday: true,
      now: now,
    );

    final last = timeline.entries.last as StayEntry;
    expect(last.ongoing, isTrue);
    expect(last.end, now);
  });

  test('no points gives an empty timeline', () {
    expect(HistoryTimelineBuilder.build(points: const []).isEmpty, isTrue);
  });
}
