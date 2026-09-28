import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../config/theme_config.dart';
import '../../../data/models/geofence_model.dart';
import '../../../services/family_service.dart';
import '../../../services/history_timeline.dart';

class MemberHistoryScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final String? photoUrl;

  const MemberHistoryScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    this.photoUrl,
  });

  @override
  State<MemberHistoryScreen> createState() => _MemberHistoryScreenState();
}

class _MemberHistoryScreenState extends State<MemberHistoryScreen> {
  static const _daysShown = 30;
  static const _fallbackCamera = LatLng(28.6139, 77.2090);

  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  GoogleMapController? _mapController;

  DayTimeline? _timeline;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  int? _selectedEntry;

  List<KnownPlace>? _places;
  final Map<String, GeofenceModel> _geofencesById = {};

  bool _isLoading = false;
  String? _error;

  /// Tapping through days quickly must not let a slow earlier response
  /// overwrite the day that is actually selected.
  int _loadToken = 0;

  bool get _isToday => DateUtils.isSameDay(_selectedDate, DateTime.now());

  @override
  void initState() {
    super.initState();
    _load(_selectedDate);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _load(DateTime date) async {
    final token = ++_loadToken;
    setState(() {
      _selectedDate = DateUtils.dateOnly(date);
      _isLoading = true;
      _error = null;
      _selectedEntry = null;
    });

    try {
      _places ??= await _loadPlaces();
      final service = FamilyService();
      final results = await Future.wait([
        service.getLocationHistory(widget.memberId, date),
        service.getLastHistoryPointBefore(widget.memberId, date),
      ]);
      if (!mounted || token != _loadToken) return;

      final raw = results[0] as List<Map<String, dynamic>>;
      final previous = results[1] as Map<String, dynamic>?;

      final timeline = HistoryTimelineBuilder.build(
        points: raw.map(HistoryPoint.fromMap).whereType<HistoryPoint>().toList(),
        previousDayLast:
            previous == null ? null : HistoryPoint.fromMap(previous),
        places: _places ?? const [],
        isToday: _isToday,
      );

      setState(() {
        _timeline = timeline;
        _isLoading = false;
        _rebuildMapObjects();
      });
      _scheduleFit();
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load history. Check your connection and try again.';
      });
    }
  }

  Future<List<KnownPlace>> _loadPlaces() async {
    final familyId = FamilyService().currentFamilyId;
    if (familyId == null) return const [];
    try {
      final geofences = await FamilyService()
          .getGeofencesStream(familyId)
          .first
          .timeout(const Duration(seconds: 6));
      _geofencesById
        ..clear()
        ..addEntries(geofences.map((g) => MapEntry(g.id, g)));
      return [
        for (final g in geofences)
          if (g.isActive)
            KnownPlace(
              id: g.id,
              name: g.name,
              latitude: g.latitude,
              longitude: g.longitude,
              radiusMeters: g.radiusMeters,
            ),
      ];
    } catch (_) {
      // Places only improve the labels; the timeline still works without them.
      return const [];
    }
  }

  // ─── Map ───

  void _rebuildMapObjects() {
    final timeline = _timeline;
    if (timeline == null) {
      _markers = {};
      _polylines = {};
      return;
    }

    final markers = <Marker>{};
    final polylines = <Polyline>{};
    final selected = _selectedEntry;

    for (var i = 0; i < timeline.entries.length; i++) {
      final entry = timeline.entries[i];
      final dimmed = selected != null && selected != i;

      switch (entry) {
        case StayEntry():
          markers.add(Marker(
            markerId: MarkerId('stay_$i'),
            position: LatLng(entry.latitude, entry.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(entry)),
            alpha: dimmed ? 0.45 : 1,
            zIndex: selected == i ? 2 : 1,
            infoWindow: InfoWindow(
              title: entry.label,
              snippet: _stayTimeRange(entry),
            ),
            onTap: () => _select(i),
          ));
        case TripEntry():
          final color = AppTheme.primaryColor.withOpacity(dimmed ? 0.3 : 1);
          final width = selected == i ? 7 : 5;
          var run = <LatLng>[LatLng(entry.path.first.latitude,
              entry.path.first.longitude)];
          var runIndex = 0;

          void flushRun() {
            if (run.length >= 2) {
              polylines.add(Polyline(
                polylineId: PolylineId('trip_${i}_$runIndex'),
                points: run,
                color: color,
                width: width,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                consumeTapEvents: true,
                onTap: () => _select(i),
              ));
              runIndex++;
            }
          }

          for (var s = 0; s < entry.path.length - 1; s++) {
            final a = LatLng(entry.path[s].latitude, entry.path[s].longitude);
            final b =
                LatLng(entry.path[s + 1].latitude, entry.path[s + 1].longitude);
            if (entry.gapSegments.contains(s)) {
              flushRun();
              // The route here was never recorded; a dashed line says so
              // instead of pretending the member drove in a straight line.
              polylines.add(Polyline(
                polylineId: PolylineId('gap_${i}_$s'),
                points: [a, b],
                color: Colors.grey.withOpacity(dimmed ? 0.3 : 0.8),
                width: 3,
                patterns: [PatternItem.dash(14), PatternItem.gap(10)],
              ));
              run = [b];
            } else {
              run.add(b);
            }
          }
          flushRun();
      }
    }

    _markers = markers;
    _polylines = polylines;
  }

  double _hueFor(StayEntry stay) {
    final geofence = _geofencesById[stay.place?.id];
    if (geofence == null) return BitmapDescriptor.hueViolet;
    switch (geofence.type) {
      case GeofenceType.home:
        return BitmapDescriptor.hueGreen;
      case GeofenceType.school:
        return BitmapDescriptor.hueAzure;
      case GeofenceType.office:
        return BitmapDescriptor.hueOrange;
      case GeofenceType.custom:
        return BitmapDescriptor.hueMagenta;
    }
  }

  void _scheduleFit() {
    // The map may not have laid out yet; bounds on a zero-sized map throw.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _fitAll();
    });
  }

  void _fitAll() {
    final timeline = _timeline;
    if (timeline == null || timeline.isEmpty) return;
    final coords = <LatLng>[
      for (final entry in timeline.entries)
        ...switch (entry) {
          StayEntry() => [LatLng(entry.latitude, entry.longitude)],
          TripEntry() =>
            entry.path.map((p) => LatLng(p.latitude, p.longitude)),
        },
    ];
    _fitCoords(coords);
  }

  void _fitCoords(List<LatLng> coords) {
    final controller = _mapController;
    if (controller == null || coords.isEmpty) return;

    var minLat = coords.first.latitude, maxLat = minLat;
    var minLng = coords.first.longitude, maxLng = minLng;
    for (final c in coords) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    // A single spot has zero-size bounds, which zooms to the maximum.
    if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2), 16));
      return;
    }
    controller.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      60,
    ));
  }

  void _select(int index) {
    final timeline = _timeline;
    if (timeline == null) return;
    final toggledOff = _selectedEntry == index;
    setState(() {
      _selectedEntry = toggledOff ? null : index;
      _rebuildMapObjects();
    });
    if (toggledOff) {
      _fitAll();
      return;
    }
    final entry = timeline.entries[index];
    switch (entry) {
      case StayEntry():
        _fitCoords([LatLng(entry.latitude, entry.longitude)]);
      case TripEntry():
        _fitCoords(
            entry.path.map((p) => LatLng(p.latitude, p.longitude)).toList());
    }
  }

  // ─── Formatting ───

  static final _time = DateFormat('h:mm a');

  String _stayTimeRange(StayEntry stay) {
    final start = stay.startedEarlier
        ? 'yesterday ${_time.format(stay.start)}'
        : _time.format(stay.start);
    if (stay.ongoing) return 'Since $start';
    if (stay.start == stay.end) return _time.format(stay.start);
    return '$start – ${_time.format(stay.end)}';
  }

  static String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '<1 min';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${d.inHours}h' : '${d.inHours}h ${minutes}m';
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
  }

  String _dayLabel(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(date, today)) return 'Today';
    if (DateUtils.isSameDay(date, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMM d').format(date);
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: AppTheme.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.memberName}\'s history',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              _dayLabel(_selectedDate),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_today_rounded,
                color: AppTheme.primaryColor),
            onPressed: () async {
              final today = DateUtils.dateOnly(DateTime.now());
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: today.subtract(const Duration(days: _daysShown - 1)),
                lastDate: today,
              );
              if (picked != null) _load(picked);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateStrip(),
          Expanded(flex: 4, child: _buildMap()),
          Expanded(flex: 5, child: _buildTimelinePanel()),
        ],
      ),
    );
  }

  Widget _buildDateStrip() {
    final today = DateUtils.dateOnly(DateTime.now());
    return Container(
      color: Colors.white,
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _daysShown,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        itemBuilder: (context, index) {
          final date = today.subtract(Duration(days: index));
          final isSelected = DateUtils.isSameDay(date, _selectedDate);
          final topLabel = index == 0
              ? 'Today'
              : DateFormat('EEE').format(date);

          return GestureDetector(
            onTap: () => _load(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 54,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: isSelected
                    ? null
                    : Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    topLabel,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white70
                          : AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    final timeline = _timeline;
    // Hold the map back until the first day has loaded so it opens on the
    // member's route instead of flashing a default city first.
    if (timeline == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final first = timeline.points.isNotEmpty ? timeline.points.first : null;
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: first == null
                ? _fallbackCamera
                : LatLng(first.latitude, first.longitude),
            zoom: first == null ? 11 : 14,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _scheduleFit();
          },
          markers: _markers,
          polylines: _polylines,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          onTap: (_) {
            if (_selectedEntry != null) _select(_selectedEntry!);
          },
        ),
        if (!timeline.isEmpty)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: 'history_fit',
              tooltip: 'Show whole day',
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryColor,
              onPressed: () {
                if (_selectedEntry != null) {
                  setState(() {
                    _selectedEntry = null;
                    _rebuildMapObjects();
                  });
                }
                _fitAll();
              },
              child: const Icon(Icons.zoom_out_map_rounded),
            ),
          ),
        if (_isLoading)
          Container(
            color: Colors.white.withOpacity(0.5),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildTimelinePanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildSummary(),
          const Divider(height: 1),
          Expanded(child: _buildTimelineBody()),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final timeline = _timeline;
    final hasData = timeline != null && !timeline.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        children: [
          _SummaryStat(
            icon: Icons.route_rounded,
            value: hasData ? _formatDistance(timeline.totalDistanceMeters) : '–',
            label: 'Travelled',
          ),
          _SummaryStat(
            icon: Icons.timer_outlined,
            value: hasData ? _formatDuration(timeline.movingTime) : '–',
            label: 'On the move',
          ),
          _SummaryStat(
            icon: Icons.place_outlined,
            value: hasData ? '${timeline.stays.length}' : '–',
            label: timeline?.stays.length == 1 ? 'Place' : 'Places',
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineBody() {
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        message: _error!,
        action: TextButton(
          onPressed: () => _load(_selectedDate),
          child: const Text('Try again'),
        ),
      );
    }

    final timeline = _timeline;
    if (timeline == null) return const SizedBox.shrink();

    if (timeline.isEmpty) {
      return _EmptyState(
        icon: Icons.location_off_rounded,
        title: 'No history for ${_dayLabel(_selectedDate).toLowerCase()}',
        message: _isToday
            ? 'Nothing has been recorded yet today. Places and trips appear '
                'here as ${widget.memberName} moves around.'
            : 'Location wasn\'t recorded on this day. The phone may have been '
                'off or sharing was paused.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: timeline.entries.length,
      itemBuilder: (context, index) {
        final entry = timeline.entries[index];
        final isFirst = index == 0;
        final isLast = index == timeline.entries.length - 1;
        final selected = _selectedEntry == index;
        return switch (entry) {
          StayEntry() => _StayTile(
              stay: entry,
              timeRange: _stayTimeRange(entry),
              duration: _formatDuration(entry.duration),
              geofence: _geofencesById[entry.place?.id],
              selected: selected,
              showTopRail: !isFirst,
              showBottomRail: !isLast,
              onTap: () => _select(index),
            ),
          TripEntry() => _TripTile(
              trip: entry,
              title: _tripTitle(entry),
              details: _tripDetails(entry),
              selected: selected,
              showBottomRail: !isLast,
              onTap: () => _select(index),
            ),
        };
      },
    );
  }

  String _tripTitle(TripEntry trip) {
    final distance = _formatDistance(trip.distanceMeters);
    return switch (trip.mode) {
      TripMode.driving => 'Drove $distance',
      TripMode.walking => 'Walked $distance',
      TripMode.unknown => 'Moved $distance',
    };
  }

  String _tripDetails(TripEntry trip) {
    final parts = <String>[
      if (trip.duration.inMinutes >= 1) ...[
        '${_time.format(trip.start)} – ${_time.format(trip.end)}',
        _formatDuration(trip.duration),
      ],
      if (trip.topSpeedMps != null && trip.mode == TripMode.driving)
        'top ${(trip.topSpeedMps! * 3.6).round()} km/h',
    ];
    return parts.join(' · ');
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryColor),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StayTile extends StatelessWidget {
  const _StayTile({
    required this.stay,
    required this.timeRange,
    required this.duration,
    required this.geofence,
    required this.selected,
    required this.showTopRail,
    required this.showBottomRail,
    required this.onTap,
  });

  final StayEntry stay;
  final String timeRange;
  final String duration;
  final GeofenceModel? geofence;
  final bool selected;
  final bool showTopRail;
  final bool showBottomRail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = geofence?.typeColor ?? const Color(0xFF8B5CF6);
    final icon = geofence?.typeIcon ?? Icons.place_rounded;
    final showAddress = stay.place != null && stay.address != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor.withOpacity(0.07) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Expanded(
                      child: showTopRail
                          ? const _Rail()
                          : const SizedBox.shrink(),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    Expanded(
                      child: showBottomRail
                          ? const _Rail()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stay.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (stay.ongoing)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Now',
                                style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (showAddress) ...[
                        const SizedBox(height: 2),
                        Text(
                          stay.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        stay.duration.inMinutes >= 1
                            ? '$timeRange · $duration'
                            : timeRange,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({
    required this.trip,
    required this.title,
    required this.details,
    required this.selected,
    required this.showBottomRail,
    required this.onTap,
  });

  final TripEntry trip;
  final String title;
  final String details;
  final bool selected;
  final bool showBottomRail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (trip.mode) {
      TripMode.driving => Icons.directions_car_rounded,
      TripMode.walking => Icons.directions_walk_rounded,
      TripMode.unknown => Icons.more_vert_rounded,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor.withOpacity(0.07) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    const Expanded(child: _Rail()),
                    Icon(icon, size: 18, color: AppTheme.textSecondary),
                    Expanded(
                      child: showBottomRail
                          ? const _Rail()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (trip.hasGap) ...[
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.gps_off_rounded,
                                size: 13, color: AppTheme.warningColor),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Part of this route wasn\'t recorded',
                                style: TextStyle(
                                  color: AppTheme.warningColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(width: 2, color: AppTheme.dividerColor),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
