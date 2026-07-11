import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../../config/theme_config.dart';
import '../../../services/family_service.dart';
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

    final historyData = await FamilyService().getLocationHistory(widget.memberId, date);

    _markers.clear();
    _polylines.clear();
    _events.clear();

    if (historyData.isNotEmpty) {
      List<LatLng> points = [];
      
      for (int i = 0; i < historyData.length; i++) {
        final data = historyData[i];
        final lat = (data['latitude'] as num).toDouble();
        final lng = (data['longitude'] as num).toDouble();
        final timestamp = data['timestamp'] as int;
        final address = data['address'] as String?;
        final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        final point = LatLng(lat, lng);
        points.add(point);
        
        bool shouldAddEvent = false;
        String title = 'Location Update';
        IconData icon = Icons.location_on;
        Color color = AppTheme.primaryColor;
        
        if (i == 0) {
          shouldAddEvent = true;
          title = 'First recorded location';
          icon = Icons.play_circle_fill;
          color = Colors.green;
        } else if (i == historyData.length - 1) {
          shouldAddEvent = true;
          title = 'Last recorded location';
          icon = Icons.stop_circle;
          color = Colors.red;
        } else {
          final prevData = historyData[i - 1];
          final prevTime = DateTime.fromMillisecondsSinceEpoch(prevData['timestamp'] as int);
          if (time.difference(prevTime).inMinutes > 30) {
             shouldAddEvent = true;
             title = 'Location update after gap';
             icon = Icons.update;
             color = Colors.orange;
          }
        }
        
        if (shouldAddEvent) {
          _events.add(HistoryEvent(
            time: time,
            title: title,
            location: address,
            icon: icon,
            color: color,
          ));
          
          _markers.add(Marker(
            markerId: MarkerId('stop_$i'),
            position: point,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              i == 0 ? BitmapDescriptor.hueGreen : (i == historyData.length - 1 ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange)
            ),
            infoWindow: InfoWindow(title: DateFormat('hh:mm a').format(time), snippet: address),
          ));
        }
      }

      if (points.isNotEmpty) {
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: AppTheme.primaryColor,
          width: 4,
          jointType: JointType.round,
        ));
      }
    } else {
      // Show empty state indicator or rely on UI to show no events
    }

    setState(() => _isLoading = false);
    
    // Fit bounds after data load
    if (_polylines.isNotEmpty && _mapController != null) {
      Future.delayed(const Duration(milliseconds: 300), _fitBounds);
    }
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
                    child: _events.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_off, size: 48, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    'No location history found',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Location data for this date was not recorded or is unavailable.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
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
    if (_polylines.isEmpty) return '0.0';
    
    double totalDistance = 0.0;
    final points = _polylines.first.points;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += _calculateDistance(
        points[i].latitude, points[i].longitude,
        points[i+1].latitude, points[i+1].longitude
      );
    }
    
    return totalDistance.toStringAsFixed(1);
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a));
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
