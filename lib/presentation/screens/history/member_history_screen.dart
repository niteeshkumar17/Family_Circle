import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../../config/theme_config.dart';
import 'dart:math' as math;

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
  DateTime _selectedDate = DateTime.now();
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<HistoryEvent> _events = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistoryForDate(_selectedDate);
  }

  Future<void> _loadHistoryForDate(DateTime date) async {
    setState(() => _isLoading = true);

    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Generate mock data based on date
    _generateMockData(date);

    setState(() => _isLoading = false);
    
    // Fit bounds after data load
    if (_polylines.isNotEmpty && _mapController != null) {
      Future.delayed(const Duration(milliseconds: 300), _fitBounds);
    }
  }

  void _generateMockData(DateTime date) {
    _markers.clear();
    _polylines.clear();
    _events.clear();

    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final random = math.Random(date.day); // Seed with day for consistent "random" data per day

    // Base location (Home)
    const homeLat = 28.6139;
    const homeLng = 77.2090;

    // Generate 3-5 stops
    int numStops = 3 + random.nextInt(3);
    List<LatLng> points = [const LatLng(homeLat, homeLng)];
    
    // Create Events
    _events.add(HistoryEvent(
      time: DateTime(date.year, date.month, date.day, 8, 30),
      title: 'Left Home',
      icon: Icons.home_rounded,
      color: Colors.green,
    ));

    double currentLat = homeLat;
    double currentLng = homeLng;

    for (int i = 0; i < numStops; i++) {
      // Move randomly
      currentLat += (random.nextDouble() - 0.5) * 0.05;
      currentLng += (random.nextDouble() - 0.5) * 0.05;
      LatLng point = LatLng(currentLat, currentLng);
      points.add(point);

      // Add marker
      _markers.add(Marker(
        markerId: MarkerId('stop_$i'),
        position: point,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          [BitmapDescriptor.hueRed, BitmapDescriptor.hueBlue, BitmapDescriptor.hueOrange][i % 3]
        ),
        infoWindow: InfoWindow(title: 'Stop ${i + 1}'),
      ));

      // Add event
      int hour = 9 + (i * 3) + random.nextInt(2);
      int minute = random.nextInt(60);
      _events.add(HistoryEvent(
        time: DateTime(date.year, date.month, date.day, hour, minute),
        title: ['Arrived at Office', 'Visited Mall', 'Stopped at Gas Station', 'Picked up Kids'][i % 4],
        icon: [Icons.work, Icons.shopping_bag, Icons.local_gas_station, Icons.school][i % 4],
        color: AppTheme.primaryColor,
        location: 'Sector ${10 + random.nextInt(50)}, Delhi',
      ));
    }

    // Return home
    points.add(const LatLng(homeLat, homeLng));
    _events.add(HistoryEvent(
      time: DateTime(date.year, date.month, date.day, 19, 45),
      title: 'Arrived at Home',
      icon: Icons.home_rounded,
      color: Colors.green,
    ));

    // Create polyline
    _polylines.add(Polyline(
      polylineId: const PolylineId('route'),
      points: points,
      color: AppTheme.primaryColor,
      width: 4,
      jointType: JointType.round,
    ));
  }

  void _fitBounds() {
    if (_polylines.isEmpty) return;
    
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    
    for (final point in _polylines.first.points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.memberName}\'s History',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              DateFormat('MMMM d, yyyy').format(_selectedDate),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryColor),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
                _loadHistoryForDate(picked);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Selector Strip
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              reverse: true, // Show newest first (right aligned typically, but let's check UX)
              // Actually standard list view starts from left. Let's not reverse, but generate dates from today backwards.
              itemCount: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              itemBuilder: (context, index) {
                final date = DateTime.now().subtract(Duration(days: index));
                final isSelected = DateUtils.isSameDay(date, _selectedDate);
                
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = date);
                    _loadHistoryForDate(date);
                  },
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        if (!isSelected)
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                      ],
                      border: isSelected ? null : Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(date).substring(0, 1),
                          style: TextStyle(
                            color: isSelected ? Colors.white70 : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
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
          ),

          // Map View
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(28.6139, 77.2090),
                    zoom: 12,
                  ),
                  onMapCreated: (controller) => _mapController = controller,
                  markers: _markers,
                  polylines: _polylines,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                ),
                if (_isLoading)
                  Container(
                    color: Colors.white.withOpacity(0.5),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),

          // Timeline
          Expanded(
            flex: 5,
            child: Container(
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
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Timeline',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_calcTotalDist()} km total',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _events.length,
                      itemBuilder: (context, index) {
                        final event = _events[index];
                        final isLast = index == _events.length - 1;
                        
                        return IntrinsicHeight(
                          child: Row(
                            children: [
                              Column(
                                children: [
                                  Text(
                                    DateFormat('h:mm a').format(event.time),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        color: Colors.grey[200],
                                        margin: const EdgeInsets.only(top: 4, bottom: 4),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: event.color.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(event.icon, color: event.color, size: 20),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        color: Colors.grey[200],
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (event.location != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          event.location!,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _calcTotalDist() {
    double dist = 0;
    if (_polylines.isEmpty) return '0.0';
    
    // Simple mock calculation for display
    return (25.5 + math.Random(_selectedDate.day).nextDouble() * 10).toStringAsFixed(1);
  }
}

class HistoryEvent {
  final DateTime time;
  final String title;
  final String? location;
  final IconData icon;
  final Color color;

  HistoryEvent({
    required this.time,
    required this.title,
    this.location,
    required this.icon,
    required this.color,
  });
}
