import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../../config/theme_config.dart';
import 'history/member_history_screen.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Map Screen')));
}

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Simulated family data with speed
    final familyMembers = [
      {'id': 'dad', 'name': 'Dad', 'status': 'At Office', 'battery': 85, 'lat': 28.6229, 'lng': 77.2195, 'speed': 0.0, 'isMoving': false},
      {'id': 'mom', 'name': 'Mom', 'status': 'Traveling', 'battery': 62, 'lat': 28.6100, 'lng': 77.2050, 'speed': 35.5, 'isMoving': true},
      {'id': 'aarav', 'name': 'Aarav', 'status': 'At School', 'battery': 45, 'lat': 28.6180, 'lng': 77.2120, 'speed': 0.0, 'isMoving': false},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF151B2C), // Dark Navy Background
      appBar: AppBar(
        title: const Text(
          'Family Members',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: () => _showInviteDialog(context),
            tooltip: 'Add Member',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: familyMembers.length,
        itemBuilder: (context, index) {
          final member = familyMembers[index];
          
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MemberDetailScreen(
                    memberId: member['id'] as String,
                    memberName: member['name'] as String,
                    status: member['status'] as String,
                    battery: member['battery'] as int,
                    lat: member['lat'] as double,
                    lng: member['lng'] as double,
                    speed: member['speed'] as double,
                    isMoving: member['isMoving'] as bool,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20), // More rounded
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                   Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                        child: Text(
                          (member['name'] as String)[0],
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member['name'] as String,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151B2C),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              member['status'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.battery_std,
                            size: 16,
                            color: (member['battery'] as int) < 50 
                                ? AppTheme.warningColor 
                                : AppTheme.successColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${member['battery']}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.grey
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '2 min ago',
                        style: TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // History Icon
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MemberHistoryScreen(
                            memberId: member['id'] as String,
                            memberName: member['name'] as String,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Direction/Navigation Icon
                  GestureDetector(
                    onTap: () {
                       Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MemberDetailScreen(
                            memberId: member['id'] as String,
                            memberName: member['name'] as String,
                            status: member['status'] as String,
                            battery: member['battery'] as int,
                            lat: member['lat'] as double,
                            lng: member['lng'] as double,
                            speed: member['speed'] as double,
                            isMoving: member['isMoving'] as bool,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.directions_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
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

  void _showInviteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Family Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this code with your family member to link them to your circle:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Text(
                'FAM-9283',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: 'FAM-9283'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied to clipboard')),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Share.share('Join my FamilyNest circle with code: FAM-9283');
              Navigator.pop(context);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  final String? userId;
  const HistoryScreen({super.key, this.userId});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('History Screen')));
}

class GeofenceScreen extends StatelessWidget {
  const GeofenceScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Geofence Screen')));
}

class CreateGeofenceScreen extends StatefulWidget {
  const CreateGeofenceScreen({super.key});

  @override
  State<CreateGeofenceScreen> createState() => _CreateGeofenceScreenState();
}

class _CreateGeofenceScreenState extends State<CreateGeofenceScreen> {
  GoogleMapController? _mapController;
  LatLng _selectedPosition = const LatLng(28.6139, 77.2090);
  double _radius = 200;
  final _nameController = TextEditingController();
  bool _isLoading = true;
  final Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final location = Location();
      final locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _selectedPosition = LatLng(locationData.latitude!, locationData.longitude!);
          _isLoading = false;
          _updateCircle();
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_selectedPosition, 15));
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      setState(() => _isLoading = false);
    }
  }

  void _updateCircle() {
    _circles.clear();
    _circles.add(
      Circle(
        circleId: const CircleId('geofence'),
        center: _selectedPosition,
        radius: _radius,
        fillColor: AppTheme.primaryColor.withOpacity(0.2),
        strokeColor: AppTheme.primaryColor,
        strokeWidth: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Geofence'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedPosition,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (!_isLoading) {
                      controller.animateCamera(
                        CameraUpdate.newLatLngZoom(_selectedPosition, 15),
                      );
                    }
                  },
                  onTap: (position) {
                    setState(() {
                      _selectedPosition = position;
                      _updateCircle();
                    });
                  },
                  circles: _circles,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                ),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                // Center marker
                const Center(
                  child: Icon(
                    Icons.location_pin,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          
          // Form section
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Place name
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Place Name',
                      hintText: 'e.g., Home, Office, School',
                      prefixIcon: const Icon(Icons.place),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Radius slider
                  Row(
                    children: [
                      const Icon(Icons.radar, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Radius: ${_radius.round()}m'),
                            Slider(
                              value: _radius,
                              min: 50,
                              max: 1000,
                              divisions: 19,
                              activeColor: AppTheme.primaryColor,
                              onChanged: (value) {
                                setState(() {
                                  _radius = value;
                                  _updateCircle();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const Spacer(),
                  
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_nameController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a place name')),
                          );
                          return;
                        }
                        // Save geofence logic here
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Geofence "${_nameController.text}" created!'),
                            backgroundColor: AppTheme.successColor,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Create Geofence',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
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
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Settings Screen')));
}

// Member Detail Screen
class MemberDetailScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final String status;
  final int battery;
  final double lat;
  final double lng;
  final double speed;
  final bool isMoving;

  const MemberDetailScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.status,
    required this.battery,
    required this.lat,
    required this.lng,
    this.speed = 0.0,
    this.isMoving = false,
  });

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  LatLng? _currentLocation;
  bool _isLoadingRoute = false;
  bool _showingRoute = false;
  double _distanceKm = 0.0;
  String _estimatedTime = '';

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  String _calculateEstimatedTime(double distanceKm) {
    // Assuming average speed of 30 km/h in city
    double timeHours = distanceKm / 30;
    int totalMinutes = (timeHours * 60).round();
    if (totalMinutes < 1) return '< 1 min';
    if (totalMinutes < 60) return '$totalMinutes min';
    int hours = totalMinutes ~/ 60;
    int mins = totalMinutes % 60;
    return '${hours}h ${mins}m';
  }

  Future<void> _getCurrentLocation() async {
    try {
      final location = Location();
      final locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }



  Future<void> _showRouteToMember() async {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting your location...')),
      );
      await _getCurrentLocation();
      if (_currentLocation == null) return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      // Directions API is now enabled!
      PolylinePoints polylinePoints = PolylinePoints();
      
      // NOTE: Using the API key from AndroidManifest.xml
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: '***REMOVED***',
        request: PolylineRequest(
          origin: PointLatLng(_currentLocation!.latitude, _currentLocation!.longitude),
          destination: PointLatLng(widget.lat, widget.lng),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        List<LatLng> routeCoords = result.points
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        // Calculate distance
        double distance = _calculateDistance(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          widget.lat,
          widget.lng,
        );

        // Real Google Maps navigation route
        final polyline = Polyline(
          polylineId: const PolylineId('route'),
          points: routeCoords,
          color: Colors.blue, 
          width: 5,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        );

        if (!mounted) return;

        setState(() {
          _polylines = {polyline};
          _isLoadingRoute = false;
          _showingRoute = true;
          _distanceKm = distance;
          _estimatedTime = _calculateEstimatedTime(distance);
        });

        // Zoom to fit route
        if (routeCoords.isNotEmpty) {
          LatLngBounds bounds = _createBounds(routeCoords);
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_formatDistance(distance)} • $_estimatedTime to ${widget.memberName}'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      } else {
        throw Exception(result.errorMessage ?? 'No route found');
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
      if (mounted) {
        setState(() => _isLoadingRoute = false);
      }
      
      // Fallback only if API completely fails (e.g. no internet)
      _drawDirectLineFallback();
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Direction Error: $e')),
      );
    }
  }

  void _drawDirectLineFallback() {
     // Fallback: simple dashed line
    final destination = LatLng(widget.lat, widget.lng);
    
    // Calculate distance
    double distance = _calculateDistance(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      widget.lat,
      widget.lng,
    );
    
    final polyline = Polyline(
      polylineId: const PolylineId('route_direct'),
      points: [_currentLocation!, destination],
      color: Colors.grey,
      width: 3,
      patterns: [PatternItem.dash(10), PatternItem.gap(10)],
    );
     setState(() {
      _polylines = {polyline};
      _showingRoute = true;
      _distanceKm = distance;
      _estimatedTime = _calculateEstimatedTime(distance);
    });
  }

  LatLngBounds _createBounds(List<LatLng> positions) {
    if (positions.isEmpty) return LatLngBounds(southwest: const LatLng(0,0), northeast: const LatLng(0,0));
    final southwestLat = positions.map((p) => p.latitude).reduce((value, element) => value < element ? value : element);
    final southwestLon = positions.map((p) => p.longitude).reduce((value, element) => value < element ? value : element);
    final northeastLat = positions.map((p) => p.latitude).reduce((value, element) => value > element ? value : element);
    final northeastLon = positions.map((p) => p.longitude).reduce((value, element) => value > element ? value : element);
    return LatLngBounds(
        southwest: LatLng(southwestLat, southwestLon),
        northeast: LatLng(northeastLat, northeastLon)
    );
  }

  // Removed _generateSmartRoute as we have real API now


  // Obsolete method removed: _createCurvedRoute

  void _clearRoute() {
    setState(() {
      _polylines = {};
      _showingRoute = false;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(widget.lat, widget.lng), 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full screen map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.lat, widget.lng),
              zoom: 16,
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: {
              // Member marker
              Marker(
                markerId: MarkerId(widget.memberId),
                position: LatLng(widget.lat, widget.lng),
                infoWindow: InfoWindow(title: widget.memberName),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
              ),
              // Current location marker (if showing route)
              if (_currentLocation != null && _showingRoute)
                Marker(
                  markerId: const MarkerId('me'),
                  position: _currentLocation!,
                  infoWindow: const InfoWindow(title: 'You'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                ),
            },
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          
          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  if (_showingRoute)
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: _clearRoute,
                        tooltip: 'Clear route',
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Loading indicator
          if (_isLoadingRoute)
            const Center(
              child: CircularProgressIndicator(),
            ),
          
          // Bottom card
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                        child: Text(
                          widget.memberName[0],
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.memberName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (widget.status != 'Traveling') ...[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: widget.isMoving ? AppTheme.warningColor : AppTheme.successColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.status,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                                if (widget.isMoving && widget.speed > 0) ...[
                                  if (widget.status != 'Traveling') const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.speed, size: 14, color: AppTheme.warningColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${widget.speed.toStringAsFixed(1)} km/h',
                                          style: const TextStyle(
                                            color: AppTheme.warningColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.battery_std,
                                size: 18,
                                color: widget.battery < 50 
                                    ? AppTheme.warningColor 
                                    : AppTheme.successColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.battery}%',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Updated 2 min ago',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      // Call button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () async {
                              try {
                                final Uri phoneUri = Uri(scheme: 'tel', path: '+919876543210');
                                await launchUrl(phoneUri);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not make call')),
                                  );
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.phone, size: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Message button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () async {
                              try {
                                final Uri smsUri = Uri(scheme: 'sms', path: '+919876543210');
                                await launchUrl(smsUri);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not open messages')),
                                  );
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.message, size: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Navigate button - shows route
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoadingRoute ? null : _showRouteToMember,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showingRoute ? AppTheme.successColor : AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _showingRoute
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.navigation, color: Colors.white, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatDistance(_distanceKm),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.directions, color: Colors.white, size: 20),
                                      SizedBox(width: 6),
                                      Text(
                                        'Navigate',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
