import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart' as handler;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart';
import '../../../config/theme_config.dart';
import '../../../config/routes.dart';
import '../../../services/account_service.dart';
import '../../../services/map_focus.dart';
import '../history/member_history_screen.dart';
import 'member_focus_card.dart';
import '../../../services/background_service.dart';
import '../../../services/device_optimization_service.dart';
import '../../../services/family_service.dart';
import '../../../services/location_service.dart';
import '../../../services/notification_service.dart';
import '../../../data/models/geofence_model.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/notification_model.dart';
import '../../../services/update_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../family/family_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isBackgroundLocationRestricted = false;
  Key _nestKey = UniqueKey();
  StreamSubscription<String>? _mapFocusSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _mapFocusSub = MapFocus.requests.listen((_) {
      if (mounted && _currentIndex != 0) setState(() => _currentIndex = 0);
    });
    
    // Check for OTA updates after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Sequential so the setup screen never lands on top of an update dialog.
      await UpdateService().checkForUpdates(context);
      await _maybePromptBackgroundSetup();
    });
  }

  /// Vendor power management silently stops location sharing, so on the skins
  /// known to do it the user is walked through the fix once rather than being
  /// left to discover a stale map days later.
  Future<void> _maybePromptBackgroundSetup() async {
    if (!await DeviceOptimizationService().shouldAutoPrompt()) return;
    if (!mounted) return;
    await Navigator.pushNamed(context, AppRoutes.backgroundSetup);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapFocusSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final status = await handler.Permission.locationAlways.status;
    if (mounted) {
      setState(() {
        _isBackgroundLocationRestricted = status != handler.PermissionStatus.granted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(),
      body: Column(
        children: [
          if (_isBackgroundLocationRestricted && (_currentIndex == 0 || _currentIndex == 1))
            _buildPermissionWarningBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildSOSButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildPermissionWarningBanner() {
    return Container(
      color: const Color(0xFFC0392B), // Premium crimson warning color
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Background Location Restricted',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Set Location to "Allow all the time" so tracking works when the app is closed.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => handler.openAppSettings(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFC0392B),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Fix Setting'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Custom Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            color: const Color(0xFF4285F4), // Blue
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flockar (No data sold)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'We care for your privacy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerSectionHeader('My Nests'),
                _buildDrawerItem(Icons.sync_rounded, 'Switch Nests', () => _showSwitchNestsSheet(context)),
                _buildDrawerItem(Icons.add_rounded, 'Add a nest', () => Navigator.pushNamed(context, AppRoutes.createFamily)),
                _buildDrawerItem(Icons.add_rounded, 'Join Nest?', () => Navigator.pushNamed(context, AppRoutes.joinFamily)),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                
                _buildDrawerItem(Icons.system_update_rounded, 'Check update', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are on the latest version'), backgroundColor: AppTheme.primaryColor),
                  );
                }),
                _buildDrawerItem(Icons.share_outlined, 'Share App', () {
                  Share.share('Keep your family safe and connected with Flockar! 🛡️\n\nGet the app for free: https://flockar.niteeshkumar.fun', subject: 'Check out Flockar!');
                }),
                _buildDrawerItem(Icons.privacy_tip_outlined, 'Privacy Policy', () {
                  Navigator.pushNamed(context, AppRoutes.privacy);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      onTap: () {
        Navigator.pop(context); // Close drawer
        onTap();
      },
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      key: _nestKey,
      index: _currentIndex,
      children: [
        MapViewContent(
          onSwitchNest: () => _showSwitchNestsSheet(context),
          isVisible: _currentIndex == 0,
        ),
        const RealFamilyScreen(),
        const SizedBox(), // SOS placeholder
        const PlacesContent(),
        const SettingsContent(),
      ],
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      height: 70,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.map_rounded, 'Map'),
          _buildNavItem(1, Icons.family_restroom_rounded, 'Family'),
          const SizedBox(width: 56), // Space for FAB
          _buildNavItem(3, Icons.place_rounded, 'Places'),
          _buildNavItem(4, Icons.settings_rounded, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSButton() {
    return SizedBox(
      width: 56,
      height: 56,
      child: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.sos),
        backgroundColor: Colors.transparent,
        elevation: 0,
        highlightElevation: 0,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B6B), Color(0xFFEE5A5A)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.sosColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
  void _showSwitchNestsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text(
                    'Switch Nests',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1), height: 1),
            // Content
            Expanded(
              child: FutureBuilder<List<FamilyInfo>>(
                future: FamilyService().getUserFamilies(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text('No nests found.', style: TextStyle(color: Colors.white54)),
                    );
                  }

                  final families = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: families.length,
                    itemBuilder: (context, index) {
                      final family = families[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
                          child: const Icon(Icons.family_restroom, color: AppTheme.primaryColor),
                        ),
                        title: Text(
                          family.familyName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          '${family.memberCount} members',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () async {
                          // Capture the messenger before the await so it is not
                          // read from a context that may already be gone.
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(context); // Close sheet
                          try {
                            // switchFamily also repoints the background tracker
                            // and geofence listeners at the new nest.
                            await FamilyService().switchFamily(family.id);
                            if (!mounted) return;
                            setState(() => _nestKey = UniqueKey());
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Switched to ${family.familyName}'),
                                backgroundColor: AppTheme.primaryColor,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Failed to switch nest'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _nestActionButton(
                        label: 'Add a nest',
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(this.context, AppRoutes.createFamily);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _nestActionButton(
                        label: 'Join a nest',
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(this.context, AppRoutes.joinFamily);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nestActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        side: const BorderSide(color: AppTheme.primaryColor),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(label),
    );
  }
}

// Map View Content
class MapViewContent extends StatefulWidget {
  const MapViewContent({super.key, this.onSwitchNest, this.isVisible = true});

  final VoidCallback? onSwitchNest;

  /// Whether the Map tab is on screen; back only closes the member card then.
  final bool isVisible;

  @override
  State<MapViewContent> createState() => _MapViewContentState();
}

class _MapViewContentState extends State<MapViewContent> {
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(28.6139, 77.2090); // Default to Delhi
  bool _isLoading = true;
  final Set<Marker> _markers = {};
  String _selectedFamilyName = "My Family"; // Current selected family
  final FamilyService _familyService = FamilyService();
  final LocationService _locationService = LocationService();
  List<FamilyMemberData> _familyMembers = [];

  StreamSubscription<List<FamilyMemberData>>? _membersSubscription;
  StreamSubscription<LocationModel>? _myLocationSubscription;

  /// The camera is auto-fitted once. Re-fitting on every position update would
  /// yank the map back while the user is panning or zooming.
  bool _hasFittedCamera = false;

  StreamSubscription<String>? _focusSubscription;
  String? _focusedId;

  /// Set when a member was opened before the map or their location was ready.
  bool _pendingFocusCamera = false;

  Set<Polyline> _routePolylines = {};
  bool _loadingRoute = false;
  String? _routeSummary;

  static const double _focusCardSpace = 280;

  @override
  void initState() {
    super.initState();
    _focusSubscription = MapFocus.requests.listen(_focusMember);
    _getCurrentLocation();
    _watchMyLocation();
    _loadFamilyMembers();
  }

  @override
  void dispose() {
    _focusSubscription?.cancel();
    _membersSubscription?.cancel();
    _myLocationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  FamilyMemberData? get _focusedMember {
    for (final m in _familyMembers) {
      if (m.id == _focusedId) return m;
    }
    return null;
  }

  void _focusMember(String memberId) {
    if (!mounted) return;
    if (_focusedId != memberId) _resetRoute();
    // An explicit focus wins over the one-off "fit everyone" on start-up.
    _hasFittedCamera = true;
    setState(() => _focusedId = memberId);
    _rebuildMarkers();
    _moveCameraToFocused();
  }

  void _moveCameraToFocused() {
    final member = _focusedMember;
    if (_mapController == null || member?.latitude == null) {
      _pendingFocusCamera = true;
      return;
    }
    _pendingFocusCamera = false;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(member!.latitude!, member.longitude!), 16),
    );
  }

  void _clearFocus() {
    if (_focusedId == null) return;
    _pendingFocusCamera = false;
    _resetRoute();
    setState(() => _focusedId = null);
    _rebuildMarkers();
  }

  void _resetRoute() {
    _routePolylines = {};
    _routeSummary = null;
    _loadingRoute = false;
  }

  Future<void> _toggleRoute() async {
    final member = _focusedMember;
    if (member?.latitude == null) return;

    if (_routePolylines.isNotEmpty) {
      setState(_resetRoute);
      _moveCameraToFocused();
      return;
    }

    final memberId = member!.id;
    final origin = _currentPosition;
    final destination = LatLng(member.latitude!, member.longitude!);
    setState(() => _loadingRoute = true);

    List<LatLng> points;
    String summary;
    bool roadRoute = true;
    try {
      final result = await PolylinePoints().getRouteBetweenCoordinates(
        googleApiKey: AppConfig.googleMapsApiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );
      if (result.points.isEmpty) {
        throw Exception(result.errorMessage ?? 'No route found');
      }
      points = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      final metres = result.totalDistanceValue ??
          _pathLengthMetres(points).round();
      final seconds = result.totalDurationValue ?? (metres / 30000 * 3600).round();
      summary = '${_formatDistance(metres)} • ${_formatDuration(seconds)} by car';
    } catch (e) {
      debugPrint('Route preview failed, drawing a straight line: $e');
      roadRoute = false;
      points = [origin, destination];
      final metres = _pathLengthMetres(points).round();
      summary = '${_formatDistance(metres)} away in a straight line';
    }

    if (!mounted || _focusedId != memberId) return;
    setState(() {
      _loadingRoute = false;
      _routeSummary = summary;
      _routePolylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: roadRoute ? AppTheme.primaryColor : Colors.grey,
          width: roadRoute ? 5 : 3,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          patterns: roadRoute
              ? const []
              : [PatternItem.dash(12), PatternItem.gap(10)],
        ),
      };
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(_boundsOf(points), 60),
    );
  }

  static double _pathLengthMetres(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += Geolocator.distanceBetween(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  static String _formatDistance(int metres) => metres < 1000
      ? '$metres m'
      : '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km';

  static String _formatDuration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return '< 1 min';
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  static LatLngBounds _boundsOf(List<LatLng> points) {
    var minLat = points.first.latitude, maxLat = minLat;
    var minLng = points.first.longitude, maxLng = minLng;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// `launchUrl` reports "cannot launch" by returning false as often as it
  /// does by throwing, so both outcomes surface the same message.
  Future<void> _launch(Uri uri, String failureMessage,
      {LaunchMode mode = LaunchMode.platformDefault}) async {
    final messenger = ScaffoldMessenger.of(context);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: mode);
    } catch (e) {
      debugPrint('Failed to launch $uri: $e');
    }
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _contact(FamilyMemberData member, String scheme, String failureMessage) {
    final phone = member.phone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available')),
      );
      return;
    }
    _launch(Uri(scheme: scheme, path: phone), failureMessage);
  }

  Widget _buildFocusCard(FamilyMemberData member) {
    return MemberFocusCard(
      key: ValueKey(member.id),
      member: member,
      showingRoute: _routePolylines.isNotEmpty,
      loadingRoute: _loadingRoute,
      routeSummary: _routeSummary,
      onClose: _clearFocus,
      onCall: () => _contact(member, 'tel', 'Could not start the call'),
      onMessage: () => _contact(member, 'sms', 'Could not open messages'),
      onHistory: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberHistoryScreen(
            memberId: member.id,
            memberName: member.displayName,
          ),
        ),
      ),
      onToggleRoute: _toggleRoute,
      onNavigate: () => _launch(
        Uri.parse('https://www.google.com/maps/dir/?api=1'
            '&destination=${member.latitude},${member.longitude}'),
        'Could not open Google Maps',
        mode: LaunchMode.externalApplication,
      ),
    );
  }

  void _watchMyLocation() {
    _myLocationSubscription = _locationService.locationStream.listen((location) {
      if (!mounted) return;
      final next = LatLng(location.latitude, location.longitude);
      // GPS jitter of a few metres is invisible at street zoom; skip the
      // rebuild rather than redrawing the map for it.
      final moved = Geolocator.distanceBetween(
            _currentPosition.latitude,
            _currentPosition.longitude,
            next.latitude,
            next.longitude,
          ) >=
          5;
      if (!moved && !_isLoading) return;
      _currentPosition = next;
      _isLoading = false;
      _rebuildMarkers(force: true);
    });
  }

  Future<void> _loadFamilyMembers() async {
    final familyId = await _familyService.getCurrentUserFamilyId();
    if (familyId == null) return;

    final familyInfo = await _familyService.getFamilyInfo(familyId);
    if (familyInfo != null && mounted) {
      setState(() => _selectedFamilyName = familyInfo.familyName);
    }

    await _membersSubscription?.cancel();
    _membersSubscription =
        _familyService.getFamilyMembersStream(familyId).listen((members) {
      if (!mounted) return;
      _familyMembers = members;
      _rebuildMarkers();
      // The card reads live member data (battery, address) even when no
      // marker moved.
      if (_focusedId != null) setState(() {});
      if (_pendingFocusCamera) _moveCameraToFocused();
    });
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
      _currentPosition = LatLng(position.latitude, position.longitude);
      _isLoading = false;
      _rebuildMarkers(force: true);
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Rebuilds the marker set, skipping the frame when nothing visible
  /// changed. The members feed fires for every presence and battery write,
  /// most of which do not move a marker. [force] is for state outside the
  /// markers (the loading spinner) that still needs a rebuild.
  void _rebuildMarkers({bool force = false}) {
    if (!mounted) return;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('me'),
        position: _currentPosition,
        infoWindow: const InfoWindow(title: 'You'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    };

    for (final member in _familyMembers) {
      if (member.isCurrentUser) continue;
      if (member.latitude == null || member.longitude == null) continue;

      final focused = member.id == _focusedId;
      markers.add(
        Marker(
          markerId: MarkerId(member.id),
          position: LatLng(member.latitude!, member.longitude!),
          consumeTapEvents: true,
          onTap: () => _focusMember(member.id),
          zIndex: focused ? 2 : 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            focused
                ? BitmapDescriptor.hueViolet
                : member.isOnline
                    ? BitmapDescriptor.hueGreen
                    : BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }

    if (!force && setEquals(markers, _markers)) return;

    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
    });

    if (!_hasFittedCamera && _mapController != null && _markers.length > 1) {
      _hasFittedCamera = true;
      _fitAllMarkers();
    }
  }

  void _fitAllMarkers() {
    if (_markers.isEmpty || _mapController == null) return;

    // Bounds around a single point would zoom all the way in.
    if (_markers.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_markers.first.position, 15),
      );
      return;
    }

    // Calculate bounds that include all markers
    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (final marker in _markers) {
      if (marker.position.latitude < minLat) minLat = marker.position.latitude;
      if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
      if (marker.position.longitude < minLng) minLng = marker.position.longitude;
      if (marker.position.longitude > maxLng) maxLng = marker.position.longitude;
    }

    // Also include current position
    if (_currentPosition.latitude < minLat) minLat = _currentPosition.latitude;
    if (_currentPosition.latitude > maxLat) maxLat = _currentPosition.latitude;
    if (_currentPosition.longitude < minLng) minLng = _currentPosition.longitude;
    if (_currentPosition.longitude > maxLng) maxLng = _currentPosition.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Animate camera to fit all markers with padding
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80), // 80px padding
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusedMember = _focusedMember;
    return PopScope(
      canPop: !(widget.isVisible && _focusedId != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearFocus();
      },
      child: Stack(
      children: [
        // Google Map
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition,
            zoom: 14,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            if (_pendingFocusCamera) {
              _moveCameraToFocused();
              return;
            }
            // Give the first member snapshot a moment to arrive before fitting.
            Future.delayed(const Duration(milliseconds: 500), () {
              if (!mounted || _hasFittedCamera) return;
              if (_markers.length > 1) _hasFittedCamera = true;
              _fitAllMarkers();
            });
          },
          onTap: (_) => _clearFocus(),
          padding: EdgeInsets.only(
            bottom: focusedMember != null ? _focusCardSpace : 0,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          markers: _markers,
          polylines: _routePolylines,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        
        // Loading indicator
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),

        // Clear of the SOS button, which is docked over the bottom bar and
        // reaches about 28dp into the map.
        Positioned(
          left: 12,
          right: 12,
          bottom: 40,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                  .animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: focusedMember != null
                ? _buildFocusCard(focusedMember)
                : const SizedBox.shrink(),
          ),
        ),
        
        // Dark Header Bar (Life360 style)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: const Color(0xFF0D0D0D),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Menu icon (hamburger)
                    GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: Icon(
                        Icons.menu,
                        color: Colors.white.withOpacity(0.8),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Family name with dropdown
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onSwitchNest,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedFamilyName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white.withOpacity(0.8),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    
                    
                    // Notification bell
                    IconButton(
                      onPressed: () => _showNotificationsSheet(context),
                      icon: Icon(
                        Icons.notifications_outlined,
                        color: Colors.white.withOpacity(0.8),
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }


  void _showNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      NotificationService().markAllAsRead();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All notifications marked as read'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                    },
                    child: const Text('Mark all read'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Notifications list
            Expanded(
              child: StreamBuilder<List<NotificationModel>>(
                stream: NotificationService().getUserNotifications(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications yet',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Join a family to receive updates',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  final notifications = snapshot.data!;
                  
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _buildNotificationItem(
                        notification: notification,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationItem({
    required NotificationModel notification,
  }) {
    IconData icon;
    Color iconColor;

    switch (notification.type) {
      case NotificationType.sos:
        icon = Icons.warning_rounded;
        iconColor = Colors.red;
        break;
      case NotificationType.geofenceEntry:
      case NotificationType.geofenceExit:
        icon = Icons.location_on;
        iconColor = AppTheme.successColor;
        break;
      case NotificationType.lowBattery:
      case NotificationType.phoneOff:
        icon = Icons.battery_alert;
        iconColor = Colors.orange;
        break;
      case NotificationType.familyJoin:
      case NotificationType.familyLeave:
        icon = Icons.group;
        iconColor = AppTheme.primaryColor;
        break;
      case NotificationType.locationRequest:
        icon = Icons.share_location;
        iconColor = AppTheme.primaryColor;
        break;
      case NotificationType.general:
      default:
        icon = Icons.info_outline;
        iconColor = AppTheme.primaryColor;
    }

    return InkWell(
      onTap: () {
        if (!notification.isRead) {
          NotificationService().markAsRead(notification.id);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: !notification.isRead ? AppTheme.primaryColor.withOpacity(0.05) : Colors.transparent,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: !notification.isRead ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 14,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        notification.timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: !notification.isRead ? AppTheme.primaryColor : AppTheme.textSecondary,
                          fontWeight: !notification.isRead ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Places Content
class PlacesContent extends StatefulWidget {
  const PlacesContent({super.key});

  @override
  State<PlacesContent> createState() => _PlacesContentState();
}

class _PlacesContentState extends State<PlacesContent> {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    
    if (userId == null) {
      return const Center(child: Text('Please log in.'));
    }
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Saved Places',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.createGeofence),
                  icon: const Icon(Icons.add_location_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                final familyId = userData?['currentFamilyId'] as String?;
                
                if (familyId == null) {
                  return const Center(child: Text('Join a family to view places.'));
                }

                return StreamBuilder<List<GeofenceModel>>(
                    stream: FamilyService().getGeofencesStream(familyId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text("Couldn't load places. Check your connection."),
                        );
                      }
                      
                      final geofences = snapshot.data ?? [];
                      final defaultPlaces = ['Home', 'Office', 'School'];
                      final displayList = <dynamic>[];
                      
                      for (final name in defaultPlaces) {
                        try {
                          final found = geofences.firstWhere((g) => g.name.toLowerCase() == name.toLowerCase());
                          displayList.add(found);
                        } catch (_) {
                          displayList.add(name);
                        }
                      }
                      
                      for (final g in geofences) {
                        if (!defaultPlaces.any((name) => name.toLowerCase() == g.name.toLowerCase())) {
                          displayList.add(g);
                        }
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          if (item is GeofenceModel) {
                            return _buildGeofenceItem(context, item);
                          } else if (item is String) {
                            return _buildPlaceholderItem(context, item);
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeofenceItem(BuildContext context, GeofenceModel geofence) {
    // Basic mapping for icons if we stored them as string, fallback to default
    IconData icon = Icons.location_on_rounded;
    Color color = AppTheme.primaryColor;
    if (geofence.name.toLowerCase().contains('home')) {
      icon = Icons.home_rounded;
      color = Colors.green;
    } else if (geofence.name.toLowerCase().contains('office') || geofence.name.toLowerCase().contains('work')) {
      icon = Icons.work_rounded;
      color = Colors.orange;
    } else if (geofence.name.toLowerCase().contains('school')) {
      icon = Icons.school_rounded;
      color = Colors.blue;
    }

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context, 
        AppRoutes.createGeofence, 
        arguments: {'existingGeofence': geofence},
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    geofence.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    '${geofence.radiusMeters.toInt()}m radius • ${geofence.monitoredMembers.isEmpty ? 'All members' : '${geofence.monitoredMembers.length} members'}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: geofence.isActive,
              onChanged: (value) async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await FamilyService()
                      .updateGeofence(geofence.copyWith(isActive: value));
                } catch (e) {
                  final denied = e is FirebaseException &&
                      e.code == 'permission-denied';
                  messenger.showSnackBar(SnackBar(
                    content: Text(denied
                        ? 'Only a nest admin can turn place alerts on or off'
                        : 'Could not update ${geofence.name}. Try again.'),
                    backgroundColor: AppTheme.errorColor,
                  ));
                }
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderItem(BuildContext context, String name) {
    // Rendered greyed out until the place is actually configured, so only the
    // icon varies by name.
    IconData icon = Icons.location_on_rounded;
    final lowerName = name.toLowerCase();
    if (lowerName.contains('home')) {
      icon = Icons.home_rounded;
    } else if (lowerName.contains('office') || lowerName.contains('work')) {
      icon = Icons.work_rounded;
    } else if (lowerName.contains('school')) {
      icon = Icons.school_rounded;
    }

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context, 
        AppRoutes.createGeofence, 
        arguments: {'initialName': name},
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.grey),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const Text(
                    'Not set up yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.createGeofence,
                arguments: {'initialName': name},
              ),
              child: const Text('Set up'),
            ),
          ],
        ),
      ),
    );
  }


}

// Settings Content
class SettingsContent extends StatefulWidget {
  const SettingsContent({super.key});

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  Map<NotificationCategory, bool> _notificationPrefs = {
    for (final c in NotificationCategory.values) c: true,
  };
  bool _locationSharingEnabled = true;
  bool _backgroundSetupNeeded = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPrefs();
    _loadLocationSharingPreference();
    _loadBackgroundHealth();
  }

  Future<void> _loadBackgroundHealth() async {
    final needed = await DeviceOptimizationService().shouldPromptSetup();
    if (mounted) setState(() => _backgroundSetupNeeded = needed);
  }

  Future<void> _loadLocationSharingPreference() async {
    final familyId = await FamilyService().getCurrentUserFamilyId();
    if (familyId == null) return;
    final enabled =
        await BackgroundLocationService().isLocationSharingEnabled(familyId);
    if (mounted) setState(() => _locationSharingEnabled = enabled);
  }

  void _showProfileDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      ),
    );

    String name = 'User';
    String phone = '';

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        name = userDoc.data()?['displayName'] ?? userDoc.data()?['name'] ?? user.displayName ?? 'User';
        phone = userDoc.data()?['phone'] ?? userDoc.data()?['phoneNumber'] ?? '';
      } else {
        name = user.displayName ?? 'User';
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    final nameController = TextEditingController(text: name);
    
    final List<String> countryCodes = [
      '+91', '+1', '+44', '+61', '+971', '+65', '+81', '+86', '+49', '+33'
    ];
    String selectedCountryCode = '+91';
    String phoneNumberPart = phone;

    for (final code in countryCodes) {
      if (phone.startsWith(code)) {
        selectedCountryCode = code;
        phoneNumberPart = phone.substring(code.length);
        break;
      }
    }
    
    final phoneController = TextEditingController(text: phoneNumberPart);
    bool isSaving = false;
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.primaryColor,
                child: Icon(Icons.person, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                enabled: !isSaving,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 56, // matching default TextField height roughly
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCountryCode,
                        items: countryCodes.map((code) => DropdownMenuItem(value: code, child: Text(code))).toList(),
                        onChanged: isSaving ? null : (value) {
                          if (value != null) setDialogState(() => selectedCountryCode = value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                      ),
                      keyboardType: TextInputType.phone,
                      enabled: !isSaving,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final newName = nameController.text.trim();
                final rawPhone = phoneController.text.trim();
                if (newName.isEmpty) return;
                
                final newPhone = rawPhone.isEmpty ? '' : '$selectedCountryCode$rawPhone';

                setDialogState(() => isSaving = true);
                
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogContext);

                try {
                  // 1. Update user document in Firestore
                  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                  final userDoc = await userRef.get();
                  
                  await userRef.set({
                    'displayName': newName,
                    'name': newName,
                    'phone': newPhone,
                    'phoneNumber': newPhone,
                  }, SetOptions(merge: true));

                  // 2. Update display name in Firebase Auth
                  try {
                    await user.updateDisplayName(newName);
                    await user.reload();
                  } catch (_) {}

                  // 3. Update display name in all members collections of user's families
                  if (userDoc.exists) {
                    final familyIds = List<String>.from(userDoc.data()?['familyIds'] ?? []);
                    for (final familyId in familyIds) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('families')
                            .doc(familyId)
                            .collection('members')
                            .doc(user.uid)
                            .update({'displayName': newName});
                      } catch (_) {}
                    }
                  }

                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Profile updated successfully'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error saving profile: $e'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                } finally {
                  setDialogState(() => isSaving = false);
                }
              },
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static const _categoryLabels = {
    NotificationCategory.places: ('Place alerts', 'Arrivals and departures'),
    NotificationCategory.battery: ('Low battery', "A member's phone is running low"),
    NotificationCategory.nest: ('Nest activity', 'Someone joins your nest'),
  };

  bool get _anyNotificationsEnabled =>
      _notificationPrefs.values.any((enabled) => enabled);

  Future<void> _loadNotificationPrefs() async {
    final prefs = await NotificationService().loadCategoryPrefs();
    if (mounted) setState(() => _notificationPrefs = prefs);
  }

  Future<void> _setNotificationCategory(
    NotificationCategory category,
    bool enabled,
  ) async {
    setState(() => _notificationPrefs = {..._notificationPrefs, category: enabled});
    try {
      await NotificationService().setCategoryEnabled(category, enabled);
    } catch (e) {
      debugPrint('Failed to save notification preference: $e');
    }
  }

  Future<void> _setAllNotificationCategories(bool enabled) async {
    for (final category in NotificationCategory.values) {
      await _setNotificationCategory(category, enabled);
    }
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Settings'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('SOS alerts'),
                subtitle: Text('Always on for safety'),
                trailing: Icon(Icons.check_circle, color: AppTheme.successColor),
              ),
              const Divider(),
              for (final category in NotificationCategory.values)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_categoryLabels[category]!.$1),
                  subtitle: Text(_categoryLabels[category]!.$2),
                  value: _notificationPrefs[category] ?? true,
                  onChanged: (value) async {
                    await _setNotificationCategory(category, value);
                    setDialogState(() {});
                  },
                  activeColor: AppTheme.primaryColor,
                ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyLocationSharing(bool enabled) async {
    final familyId = await FamilyService().getCurrentUserFamilyId();
    if (familyId == null) return;
    await BackgroundLocationService()
        .setLocationSharingEnabled(familyId, enabled);
    if (enabled) BackgroundLocationService().forceUpdate();
  }

  void _showLocationSharingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Sharing'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 60, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Share My Location'),
                subtitle: Text(_locationSharingEnabled 
                    ? 'Your family can see your location' 
                    : 'Your location is hidden'),
                value: _locationSharingEnabled,
                onChanged: (value) async {
                  setDialogState(() => _locationSharingEnabled = value);
                  if (mounted) setState(() {});
                  // Persist it, otherwise the switch only moved on screen and
                  // the tracker kept publishing regardless.
                  await _applyLocationSharing(value);
                },
                activeColor: AppTheme.primaryColor,
              ),
              const SizedBox(height: 8),
              Text(
                _locationSharingEnabled 
                    ? '📍 Location sharing is ON' 
                    : '🔒 Location sharing is OFF',
                style: TextStyle(
                  color: _locationSharingEnabled ? AppTheme.successColor : AppTheme.errorColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog() async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      ),
    );
    
    // Get the actual invite code from family service
    final familyService = FamilyService();
    String? inviteCode;
    DateTime? expiresAt;
    
    try {
      inviteCode = await familyService.getInviteCode();
      expiresAt = await familyService.getInviteCodeExpiry();
    } catch (e) {
      // Handle error
    }
    
    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog
    
    if (inviteCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get invite code'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    String getExpiryText() {
      if (expiresAt == null) return 'Code may be expired';
      final now = DateTime.now();
      if (expiresAt.isBefore(now)) return 'Expired - tap to regenerate';
      final diff = expiresAt.difference(now);
      if (diff.inHours > 0) return 'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
      return 'Expires in ${diff.inMinutes}m';
    }
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_rounded, color: AppTheme.primaryColor, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Invite Members',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share this code with family members',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              
              // Code Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor.withOpacity(0.08), AppTheme.primaryLight.withOpacity(0.08)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      inviteCode!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: inviteCode!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code copied to clipboard!'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, color: AppTheme.primaryColor, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Copy Code',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.textHint),
                  const SizedBox(width: 4),
                  Text(
                    getExpiryText(),
                    style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await Share.share(
                          'You\'re invited to join my secure Nest on Flockar! 🛡️\n\nTo join, enter this invite code in the app: $inviteCode\n\nDownload the app here: https://flockar.niteeshkumar.fun',
                          subject: 'Join my Nest on Flockar',
                        );
                      },
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(color: AppTheme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Actually sign out from Firebase and Google
              context.read<AuthBloc>().add(AuthLogoutRequested());
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.login,
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'Your account will be deactivated right away and removed from your nests\' maps.\n\n'
          'You can recover it by signing in again with the same Google account within '
          '${AccountService.recoveryDays} days. After that, your profile, location history '
          'and nest memberships are permanently deleted, along with any nest where you are '
          'the only member.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final DateTime deleteOn;
    try {
      deleteOn = await AccountService().requestDeletion();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Account Deleted'),
        content: Text(
          'Your account is scheduled for permanent deletion on '
          '${AccountService.formatDate(deleteOn)}.\n\n'
          'Changed your mind? Sign in with the same Google account before then to '
          'recover everything. After that date all your data will be permanently deleted.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    context.read<AuthBloc>().add(AuthLogoutRequested());
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          _buildSettingsSection(context, 'Account', [
            _buildSettingsTile(context, 'Profile', Icons.person_outline_rounded, _showProfileDialog),
            _buildSettingsTile(context, 'Notifications', Icons.notifications_outlined, _showNotificationsDialog, 
                trailing: Switch(
                  value: _anyNotificationsEnabled,
                  onChanged: _setAllNotificationCategories,
                  activeColor: AppTheme.primaryColor,
                )),
            _buildSettingsTile(context, 'Location Sharing', Icons.location_on_outlined, _showLocationSharingDialog,
                trailing: Switch(
                  value: _locationSharingEnabled,
                  onChanged: (v) async {
                    setState(() => _locationSharingEnabled = v);
                    await _applyLocationSharing(v);
                  },
                  activeColor: AppTheme.primaryColor,
                )),
            _buildSettingsTile(
              context,
              'Background Updates',
              Icons.battery_charging_full_rounded,
              () async {
                await Navigator.pushNamed(context, AppRoutes.backgroundSetup);
                await _loadBackgroundHealth();
              },
              trailing: _backgroundSetupNeeded
                  ? const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warningColor)
                  : null,
            ),
          ]),
          const SizedBox(height: 16),
          _buildSettingsSection(context, 'Family', [
            _buildSettingsTile(context, 'Manage Nest', Icons.family_restroom_outlined,
                () => Navigator.pushNamed(context, AppRoutes.manageNest)),
            _buildSettingsTile(context, 'Invite Members', Icons.person_add_outlined, _showInviteDialog),
            _buildSettingsTile(context, 'Join a Nest', Icons.group_add_outlined, () => Navigator.pushNamed(context, AppRoutes.joinFamily)),
          ]),
          const SizedBox(height: 16),
          _buildSettingsSection(context, 'Support', [
            _buildSettingsTile(context, 'Privacy Policy', Icons.privacy_tip_outlined, 
                () => Navigator.pushNamed(context, AppRoutes.privacy)),
            _buildSettingsTile(context, 'Terms of Service', Icons.description_outlined,
                () => Navigator.pushNamed(context, AppRoutes.terms)),
            _buildSettingsTile(context, 'Help & Support', Icons.help_outline_rounded,
                () => Navigator.pushNamed(context, AppRoutes.helpSupport)),
          ]),
          const SizedBox(height: 16),
          _buildSettingsSection(context, 'Account Actions', [
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppTheme.errorColor),
              title: const Text('Sign Out', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w500)),
              onTap: _showSignOutDialog,
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: AppTheme.errorColor),
              title: const Text('Delete Account', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w500)),
              onTap: _showDeleteAccountDialog,
            ),
          ]),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Flockar v1.0.0',
              style: TextStyle(color: AppTheme.textHint, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.primaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(BuildContext context, String title, IconData icon, VoidCallback onTap, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      onTap: onTap,
    );
  }
}
