import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../config/theme_config.dart';
import '../../data/models/geofence_model.dart';
import '../../services/background_service.dart';
import '../../services/family_service.dart';

class CreateGeofenceScreen extends StatefulWidget {
  final GeofenceModel? existingGeofence;
  final String? initialName;
  
  const CreateGeofenceScreen({
    super.key,
    this.existingGeofence,
    this.initialName,
  });

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
    if (widget.existingGeofence != null) {
      _selectedPosition = LatLng(widget.existingGeofence!.latitude, widget.existingGeofence!.longitude);
      _radius = widget.existingGeofence!.radiusMeters;
      _nameController.text = widget.existingGeofence!.name;
      _isLoading = false;
      _updateCircle();
    } else {
      if (widget.initialName != null) {
        _nameController.text = widget.initialName!;
      }
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      if (!await LocationPermissionHelper.requestPermissions()) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {
        _selectedPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
        _updateCircle();
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedPosition, 15),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) setState(() => _isLoading = false);
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
        title: Text(widget.existingGeofence != null ? 'Update Geofence' : 'Create Geofence'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.existingGeofence != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmDelete(context, widget.existingGeofence!),
            ),
        ],
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
                      onPressed: () async {
                        final name = _nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a place name')),
                          );
                          return;
                        }
                        
                        final familyId = FamilyService().currentFamilyId;
                        if (familyId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Error: No active family found')),
                          );
                          return;
                        }

                        // Save geofence logic here
                        setState(() => _isLoading = true);
                        try {
                          final geofence = GeofenceModel(
                            id: widget.existingGeofence?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                            familyId: familyId,
                            name: name,
                            type: GeofenceType.custom,
                            latitude: _selectedPosition.latitude,
                            longitude: _selectedPosition.longitude,
                            radiusMeters: _radius,
                            createdBy: widget.existingGeofence?.createdBy ?? FamilyService().currentUserId ?? 'unknown',
                            createdAt: widget.existingGeofence?.createdAt ?? DateTime.now(),
                            settings: widget.existingGeofence?.settings ?? GeofenceSettings(),
                            isActive: widget.existingGeofence?.isActive ?? true,
                          );
                          
                          if (widget.existingGeofence != null) {
                            await FamilyService().updateGeofence(geofence);
                          } else {
                            await FamilyService().addGeofence(geofence);
                          }
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Geofence "$name" created!'),
                                backgroundColor: AppTheme.successColor,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setState(() => _isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
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

  void _confirmDelete(BuildContext context, GeofenceModel geofence) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Place'),
        content: Text('Are you sure you want to delete "${geofence.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              navigator.pop(); // Close dialog
              try {
                await FamilyService()
                    .deleteGeofence(geofence.familyId, geofence.id);
                navigator.pop(); // Go back to Places tab
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Could not delete place: $e')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
