import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import '../config/app_config.dart';
import '../firebase_options.dart';
import 'location_cache_service.dart';
import 'tracker_watchdog.dart';
import 'dart:math' as math;

/// Keys used to share state between the UI isolate and the background isolate.
///
/// The background isolate has no access to the UI isolate's memory, so all
/// identity and configuration is passed through [SharedPreferences] (durable,
/// survives process death) and mirrored over service messages (immediate).
class BgPrefsKeys {
  static const userId = 'userId';

  /// Comma separated list of every family the user shares location with.
  static const familyIds = 'familyIds';

  /// The family currently selected in the UI. Kept for backwards compatibility
  /// and used as the fallback when [familyIds] is absent.
  static const activeFamilyId = 'familyId';

  static const lastLat = 'bg_last_lat';
  static const lastLng = 'bg_last_lng';
  static const status = 'bg_service_status';

  /// 'moving' or 'resting'; see the motion regime notes in [AppConfig].
  static const mode = 'bg_service_mode';
  static const lastError = 'bg_service_last_error';
  static const lastPush = 'bg_service_last_push';
  static const lastFix = 'bg_service_last_fix';
  static const lastStart = 'bg_service_last_start';

  static String sharingEnabled(String familyId) =>
      'location_sharing_enabled_$familyId';
}

/// Background Location Service
///
/// Owns location tracking for the whole app. This is the single writer for
/// `locations/`, `locationHistory/` and `presence/` in Realtime Database, so
/// that foreground and background never race each other on the same keys.
///
/// GPS is read through `geolocator` rather than the `location` package: the
/// background isolate is attached to an Android Service and never to an
/// Activity, and the `location` plugin rejects every request with `NO_ACTIVITY`
/// in that situation. `geolocator` binds to the application context instead and
/// works headless.
class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isInitialized = false;

  /// Initialize the background service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Start manually in Dart after permission check
        isForegroundMode: true, // Required for Android 10+
        notificationChannelId: 'family_nest_location',
        initialNotificationTitle: 'Flockar',
        initialNotificationContent: 'Location sharing is active',
        foregroundServiceNotificationId: 889,
        autoStartOnBoot: true, // Survive device reboots
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isInitialized = true;
  }

  /// Start the background service.
  ///
  /// Refuses to start without location permission: Android 14 kills a
  /// location-type foreground service that starts without it.
  Future<bool> start() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!await LocationPermissionHelper.hasAllPermissions()) {
      debugPrint('BackgroundLocationService: location permission missing, not starting');
      return false;
    }

    if (await _service.isRunning()) return true;
    return _service.startService();
  }

  /// Stop the background service
  Future<void> stop() async {
    _service.invoke('stopService');
  }

  /// Check if service is running
  Future<bool> isRunning() async {
    return _service.isRunning();
  }

  /// Update user ID for location tracking (persists + notifies service)
  Future<void> setUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BgPrefsKeys.userId, userId);
    _service.invoke('setUserId', {'userId': userId});
  }

  /// Set the family that the UI currently has selected.
  Future<void> setFamilyId(String familyId) async {
    await setFamilyIds([familyId], activeFamilyId: familyId);
  }

  /// Set every family the user belongs to.
  ///
  /// Location is published to all of them, so a user in several nests stays
  /// visible in each one instead of only the nest that happens to be open.
  Future<void> setFamilyIds(
    List<String> familyIds, {
    String? activeFamilyId,
  }) async {
    final unique = familyIds.where((id) => id.isNotEmpty).toSet().toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BgPrefsKeys.familyIds, unique.join(','));
    final active = activeFamilyId ?? (unique.isNotEmpty ? unique.first : '');
    await prefs.setString(BgPrefsKeys.activeFamilyId, active);
    _service.invoke('setFamilyIds', {'familyIds': unique, 'activeFamilyId': active});
  }

  /// Configure background service with user and family IDs.
  /// Call this after login and whenever the active family changes.
  Future<void> configureForUser({
    required String userId,
    required String familyId,
    List<String>? allFamilyIds,
  }) async {
    await setUserId(userId);
    await setFamilyIds(
      allFamilyIds ?? [familyId],
      activeFamilyId: familyId,
    );
    await start();
    forceUpdate();
    // Outlives this process, so the tracker comes back if an OEM cleaner
    // kills it while nobody is looking at the phone.
    await TrackerWatchdog.schedule();
  }

  /// Clear user data (call on sign-out)
  Future<void> clearUser() async {
    await TrackerWatchdog.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(BgPrefsKeys.userId);
    await prefs.remove(BgPrefsKeys.familyIds);
    await prefs.remove(BgPrefsKeys.activeFamilyId);
    await prefs.remove(BgPrefsKeys.lastLat);
    await prefs.remove(BgPrefsKeys.lastLng);
    _service.invoke('setUserId', {'userId': ''});
    _service.invoke('setFamilyIds', {'familyIds': <String>[], 'activeFamilyId': ''});
  }

  /// Enable/disable location sharing for a specific family
  Future<void> setLocationSharingEnabled(String familyId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(BgPrefsKeys.sharingEnabled(familyId), enabled);
    _service.invoke('setLocationSharing', {'familyId': familyId, 'enabled': enabled});
  }

  Future<bool> isLocationSharingEnabled(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(BgPrefsKeys.sharingEnabled(familyId)) ?? true;
  }

  /// Set tracking interval
  void setTrackingInterval(int seconds) {
    _service.invoke('setInterval', {'seconds': seconds});
  }

  /// Request an immediate GPS read and publish, bypassing the interval.
  void forceUpdate() {
    _service.invoke('forceUpdate');
  }

  /// Enable SOS mode (high frequency tracking)
  void enableSOSMode() {
    _service.invoke('enableSOSMode');
  }

  /// Disable SOS mode
  void disableSOSMode() {
    _service.invoke('disableSOSMode');
  }

  /// Tell the service whether the app is currently visible, so it can label
  /// presence correctly and back off while the UI is driving updates.
  void setAppVisible(bool visible) {
    _service.invoke('setAppVisible', {'visible': visible});
  }

  /// Live location updates emitted by the tracking isolate.
  Stream<Map<String, dynamic>?> get onLocationUpdate =>
      _service.on('locationUpdate');

  /// Diagnostics for the settings/debug UI, so silent failures are visible.
  Future<BackgroundServiceDiagnostics> getDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return BackgroundServiceDiagnostics(
      isRunning: await _service.isRunning(),
      status: prefs.getString(BgPrefsKeys.status) ?? 'unknown',
      mode: prefs.getString(BgPrefsKeys.mode),
      lastError: prefs.getString(BgPrefsKeys.lastError),
      lastPush: _parseDate(prefs.getString(BgPrefsKeys.lastPush)),
      lastFix: _parseDate(prefs.getString(BgPrefsKeys.lastFix)),
      lastStart: _parseDate(prefs.getString(BgPrefsKeys.lastStart)),
    );
  }

  static DateTime? _parseDate(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw);
}

class BackgroundServiceDiagnostics {
  final bool isRunning;
  final String status;
  final String? mode;
  final String? lastError;
  final DateTime? lastPush;
  final DateTime? lastFix;
  final DateTime? lastStart;

  const BackgroundServiceDiagnostics({
    required this.isRunning,
    required this.status,
    this.mode,
    this.lastError,
    this.lastPush,
    this.lastFix,
    this.lastStart,
  });

  bool get isResting => mode == 'resting';

  bool get isHealthy {
    if (!isRunning || lastPush == null) return false;
    // Resting only heartbeats every 5–10 minutes; a 10-minute window would
    // flip the health card red between ticks even though nothing is wrong.
    final limitMinutes = isResting ? 15 : 10;
    return DateTime.now().difference(lastPush!).inMinutes < limitMinutes;
  }

  /// When [lastError] was recorded. Entries are stored as
  /// `<iso8601> <status>: <details>`.
  DateTime? get lastErrorAt {
    final raw = lastError;
    if (raw == null) return null;
    final firstSpace = raw.indexOf(' ');
    if (firstSpace <= 0) return null;
    return DateTime.tryParse(raw.substring(0, firstSpace));
  }

  /// A sentence the user can act on, or null when there is nothing to report.
  ///
  /// The raw entry is an internal status code and an exception's `toString()`,
  /// which is useful in a log and meaningless on screen.
  String? get problem {
    final raw = lastError;
    if (raw == null) return null;

    // A fix that landed after the failure means it already recovered.
    final at = lastErrorAt;
    if (at != null && lastPush != null && !lastPush!.isBefore(at)) return null;

    final text = raw.toLowerCase();
    if (text.contains('location service on the device is disabled')) {
      return 'Location is switched off on this phone. Turn it on to keep '
          'sharing.';
    }
    if (text.contains('permission')) {
      return 'Flockar no longer has permission to read your location.';
    }
    if (text.contains('timeout') || text.contains('timeoutexception')) {
      return 'Could not get a GPS fix. This usually clears once you are '
          'outdoors again.';
    }
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('unavailable')) {
      return 'No connection, so the last position has not been uploaded yet.';
    }
    return 'Sharing hit a problem and is retrying in the background.';
  }
}

/// Main background service entry point
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    await prefs.setString(BgPrefsKeys.status, 'starting');
    await prefs.setString(
        BgPrefsKeys.lastStart, DateTime.now().toIso8601String());
    await prefs.remove(BgPrefsKeys.lastError);
  } catch (_) {}

  /// Records what the service is doing where the UI can read it. Previously
  /// every failure here was swallowed by a bare `catch (_)`, which is why a
  /// completely non-functional tracker still looked healthy.
  Future<void> log(String status, {Object? error}) async {
    if (error != null) {
      debugPrint('BackgroundLocationService [$status]: $error');
    }
    try {
      await prefs?.setString(BgPrefsKeys.status, status);
      if (error != null) {
        await prefs?.setString(
          BgPrefsKeys.lastError,
          '${DateTime.now().toIso8601String()} $status: $error',
        );
      }
    } catch (_) {}
  }

  try {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      // On Android the native SDK has usually already created the default app
      // from google-services.json; that duplicate is expected and harmless.
      if (!e.toString().contains('duplicate-app') &&
          !e.toString().contains('already exists')) {
        await log('firebase_init_failed', error: e);
      }
    }

    // ─── State ───
    String? userId;
    List<String> familyIds = [];
    String? activeFamilyId;
    final Map<String, bool> sharingByFamily = {};
    bool sosMode = false;
    bool appVisible = false;

    int trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
    int subscribedIntervalSeconds = -1;
    LocationAccuracy? subscribedAccuracy;

    double? lastLat;
    double? lastLng;
    String? lastAddress;
    double? lastGeocodedLat;
    double? lastGeocodedLng;

    DateTime? lastPublishTime;
    DateTime? lastFixTime;
    DateTime? lastPresenceWrite;
    DateTime? lastStallRecovery;
    String? lastNotification;
    double? lastHistoryLat;
    double? lastHistoryLng;
    DateTime? lastHistoryTime;
    String? presenceRegisteredUserId;

    // Motion regime. The GPS stream stays on only while [resting] is false.
    // A phone left on a nightstand used to keep high-accuracy GNSS running
    // all night, which is what produced the 10% per hour drain.
    var resting = false;
    var deepResting = false;
    DateTime? stillSince;
    double? stillAnchorLat;
    double? stillAnchorLng;
    Timer? restTimer;
    StreamSubscription<Position>? positionSubscription;

    // Declared up front because Dart local functions cannot call a sibling
    // that is written later in the same block.
    late Future<void> Function(Position position) considerMotion;
    late Future<void> Function({bool force}) subscribeToPositions;
    late Future<void> Function() restHeartbeat;
    late Future<void> Function() writePresence;
    late void Function() scheduleRestHeartbeat;

    final battery = Battery();
    final connectivity = Connectivity();
    final database = FirebaseDatabase.instance;
    final store = prefs ??= await SharedPreferences.getInstance();
    final tracker = BatteryOptimizedTracker();

    // Keep writes queued while offline instead of dropping them.
    try {
      database.setPersistenceEnabled(true);
    } catch (_) {
      // Already enabled, or unsupported on this platform.
    }

    bool sharingEnabledFor(String familyId) =>
        sharingByFamily[familyId] ??
        store.getBool(BgPrefsKeys.sharingEnabled(familyId)) ??
        true;

    List<String> targetFamilies() =>
        familyIds.where(sharingEnabledFor).toList();

    Future<void> reloadIdentity() async {
      try {
        await store.reload();
      } catch (_) {}
      userId = store.getString(BgPrefsKeys.userId);
      final rawIds = store.getString(BgPrefsKeys.familyIds) ?? '';
      final parsed =
          rawIds.split(',').where((id) => id.trim().isNotEmpty).toList();
      if (parsed.isEmpty) {
        final legacy = store.getString(BgPrefsKeys.activeFamilyId);
        familyIds = (legacy != null && legacy.isNotEmpty) ? [legacy] : [];
      } else {
        familyIds = parsed;
      }
      activeFamilyId = store.getString(BgPrefsKeys.activeFamilyId);
      lastLat ??= store.getDouble(BgPrefsKeys.lastLat);
      lastLng ??= store.getDouble(BgPrefsKeys.lastLng);
    }

    Future<Map<String, dynamic>> buildPayload(Position position) async {
      int batteryLevel = 100;
      bool isCharging = false;
      try {
        batteryLevel = await battery.batteryLevel;
        final bs = await battery.batteryState;
        isCharging = bs == BatteryState.charging || bs == BatteryState.full;
      } catch (_) {}

      String networkStatus = 'unknown';
      try {
        final cr = await connectivity.checkConnectivity();
        if (cr.contains(ConnectivityResult.wifi)) {
          networkStatus = 'wifi';
        } else if (cr.contains(ConnectivityResult.mobile)) {
          networkStatus = 'mobile';
        } else {
          networkStatus = 'offline';
        }
      } catch (_) {}

      // Reverse geocoding is slow and rate limited, so reuse the cached label
      // until the user has actually moved away from where it was resolved.
      final movedSinceGeocode = lastGeocodedLat == null ||
          lastGeocodedLng == null ||
          Geolocator.distanceBetween(
                lastGeocodedLat!,
                lastGeocodedLng!,
                position.latitude,
                position.longitude,
              ) >
              AppConfig.historyMinDistanceMeters;

      if (lastAddress == null || movedSinceGeocode) {
        try {
          final placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          ).timeout(const Duration(seconds: 5));
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            final parts = <String>[
              if (place.name != null && place.name!.isNotEmpty) place.name!,
              if (place.subLocality != null && place.subLocality!.isNotEmpty)
                place.subLocality!,
              if (place.locality != null && place.locality!.isNotEmpty)
                place.locality!,
            ];
            if (parts.isNotEmpty) {
              lastAddress = parts.take(3).join(', ');
              lastGeocodedLat = position.latitude;
              lastGeocodedLng = position.longitude;
            }
          }
        } catch (_) {
          // Geocoding is best effort; coordinates still publish without it.
        }
      }

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'address': lastAddress,
        'battery': batteryLevel,
        'isCharging': isCharging,
        'networkStatus': networkStatus,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isActive': true,
      };
    }

    /// Breadcrumbs are only worth storing when the user actually moved, or
    /// once enough time has passed to prove they are still somewhere.
    bool shouldRecordHistory(
        double lat, double lng, double? accuracy, DateTime now) {
      if (accuracy != null && accuracy > AppConfig.historyMaxAccuracyMeters) {
        return false;
      }
      if (lastHistoryTime == null ||
          lastHistoryLat == null ||
          lastHistoryLng == null) {
        return true;
      }
      if (now.difference(lastHistoryTime!).inSeconds >=
          AppConfig.historyMaxIntervalSeconds) {
        return true;
      }
      return Geolocator.distanceBetween(
            lastHistoryLat!,
            lastHistoryLng!,
            lat,
            lng,
          ) >=
          AppConfig.historyMinDistanceMeters;
    }

    Future<bool> publish(Map<String, dynamic> data) async {
      final uid = userId;
      final families = targetFamilies();
      if (uid == null || uid.isEmpty || families.isEmpty) return false;

      final now = DateTime.now();
      final lat = data['latitude'] as double;
      final lng = data['longitude'] as double;
      final recordHistory = shouldRecordHistory(
          lat, lng, (data['accuracy'] as num?)?.toDouble(), now);
      final dateKey = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final timestamp = data['timestamp'];

      var anySucceeded = false;
      for (final familyId in families) {
        try {
          await database.ref('locations/$familyId/$uid').set(data);
          anySucceeded = true;
        } on FirebaseException catch (e) {
          await log('push_failed_${e.code}', error: e.message ?? e.code);
          try {
            await LocationCacheService().cacheLocation(
              userId: uid,
              familyId: familyId,
              locationData: data,
            );
          } catch (cacheError) {
            await log('cache_failed', error: cacheError);
          }
          continue;
        } catch (e) {
          await log('push_failed', error: e);
          continue;
        }

        if (recordHistory) {
          try {
            await database
                .ref('locationHistory/$familyId/$uid/$dateKey/$timestamp')
                .set({
              'latitude': lat,
              'longitude': lng,
              'accuracy': data['accuracy'],
              'speed': data['speed'],
              'address': data['address'],
              'battery': data['battery'],
              'isCharging': data['isCharging'],
              'timestamp': timestamp,
            });
          } catch (e) {
            await log('history_write_failed', error: e);
          }
        }
      }

      if (anySucceeded && recordHistory) {
        lastHistoryLat = lat;
        lastHistoryLng = lng;
        lastHistoryTime = now;
      }
      return anySucceeded;
    }

    Future<void> configurePresenceOnDisconnect(String uid) async {
      if (presenceRegisteredUserId != null && presenceRegisteredUserId != uid) {
        try {
          await database
              .ref('presence/$presenceRegisteredUserId')
              .onDisconnect()
              .cancel();
        } catch (_) {}
      }
      try {
        await database.ref('presence/$uid').onDisconnect().update({
          'online': false,
          'lastSeen': ServerValue.timestamp,
          'appState': 'offline',
        });
        presenceRegisteredUserId = uid;
      } catch (e) {
        await log('presence_ondisconnect_failed', error: e);
      }
    }

    void setNotification(String content) {
      if (lastNotification == content) return;
      lastNotification = content;
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Flockar',
          content: content,
        );
      }
    }

    Future<void> persistMode() async {
      try {
        await store.setString(
            BgPrefsKeys.mode, resting ? 'resting' : 'moving');
      } catch (_) {}
    }

    LocationSettings buildSettings({
      required LocationAccuracy accuracy,
      required int intervalSeconds,
      double distanceFilter = 0,
    }) {
      if (Platform.isAndroid) {
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter.round(),
          intervalDuration: Duration(seconds: intervalSeconds),
        );
      }
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.round(),
        pauseLocationUpdatesAutomatically: !sosMode,
        showBackgroundLocationIndicator: sosMode,
        allowBackgroundLocationUpdates: true,
      );
    }

    /// Publishes a fix, applying the interval and distance throttles.
    Future<void> handlePosition(Position position, {bool force = false}) async {
      lastFixTime = DateTime.now();
      try {
        await store
            .setString(BgPrefsKeys.lastFix, lastFixTime!.toIso8601String());
      } catch (_) {}

      await considerMotion(position);

      if (userId == null || userId!.isEmpty) return;
      if (targetFamilies().isEmpty) return;

      final now = DateTime.now();
      if (!force && lastPublishTime != null) {
        final elapsed = now.difference(lastPublishTime!).inSeconds;
        final moved = (lastLat != null && lastLng != null)
            ? Geolocator.distanceBetween(
                lastLat!, lastLng!, position.latitude, position.longitude)
            : double.infinity;

        // Publish when the interval is up, or early when the user has clearly
        // moved: waiting out a 60s stationary interval while someone starts
        // driving is what made updates feel frozen.
        final intervalElapsed = elapsed >= trackingIntervalSeconds;
        final movedFar = moved >= AppConfig.publishMinDistanceMeters;
        if (!intervalElapsed && !movedFar) return;
      }

      if (!sosMode && !resting) {
        final next = tracker.calculateOptimalInterval(position.speed);
        // Ignore one-tick speed jitter so we do not tear down and rebuild
        // the GPS subscription every few seconds.
        if ((next - trackingIntervalSeconds).abs() >= 15) {
          trackingIntervalSeconds = next;
          await subscribeToPositions();
        }
      }

      final data = await buildPayload(position);
      final published = await publish(data);

      lastLat = position.latitude;
      lastLng = position.longitude;
      lastPublishTime = now;

      try {
        await store.setDouble(BgPrefsKeys.lastLat, position.latitude);
        await store.setDouble(BgPrefsKeys.lastLng, position.longitude);
      } catch (_) {}

      if (published) {
        try {
          await store.setString(BgPrefsKeys.lastPush, now.toIso8601String());
          // Whatever went wrong earlier is over: without this the last failure
          // stays pinned in the settings UI next to a live "Sharing is live".
          await store.remove(BgPrefsKeys.lastError);
        } catch (_) {}
        await log(resting ? 'resting' : 'publishing');
        service.invoke('locationUpdate', data);
      }
    }

    double? distanceFromAnchor(Position position) {
      if (stillAnchorLat == null || stillAnchorLng == null) return null;
      return Geolocator.distanceBetween(
        stillAnchorLat!,
        stillAnchorLng!,
        position.latitude,
        position.longitude,
      );
    }

    void resetStillAnchor(Position position) {
      stillAnchorLat = position.latitude;
      stillAnchorLng = position.longitude;
      stillSince = DateTime.now();
    }

    /// Turns the GPS radio off and switches to a cheap coarse heartbeat.
    Future<void> enterRest() async {
      if (resting) return;
      resting = true;
      await positionSubscription?.cancel();
      positionSubscription = null;
      subscribedIntervalSeconds = -1;
      subscribedAccuracy = null;
      await persistMode();
      setNotification('Sharing on, saving battery');
      await log('resting');
      scheduleRestHeartbeat();
    }

    scheduleRestHeartbeat = () {
      restTimer?.cancel();
      final period = deepResting
          ? AppConfig.deepRestHeartbeatSeconds
          : AppConfig.stationaryHeartbeatSeconds;
      restTimer = Timer.periodic(
        Duration(seconds: period),
        (_) => restHeartbeat(),
      );
    };

    Future<void> wakeFromRest() async {
      if (!resting) return;
      resting = false;
      deepResting = false;
      restTimer?.cancel();
      restTimer = null;
      stillSince = DateTime.now();
      await persistMode();
      setNotification('Location sharing is active');
      await log('moving');
      await subscribeToPositions(force: true);
    }

    /// Cheap WiFi/cell sample used instead of GNSS while the phone is still.
    restHeartbeat = () async {
      await writePresence();

      final stillFor = stillSince == null
          ? 0
          : DateTime.now().difference(stillSince!).inSeconds;
      if (!deepResting && stillFor >= AppConfig.deepRestAfterSeconds) {
        deepResting = true;
        scheduleRestHeartbeat();
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        await log('location_services_off');
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: buildSettings(
            accuracy: LocationAccuracy.low,
            intervalSeconds: 10,
          ),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (position == null) return;
      await handlePosition(position, force: true);
    };

    considerMotion = (Position position) async {
      if (sosMode) {
        if (resting) await wakeFromRest();
        resetStillAnchor(position);
        return;
      }

      final fromAnchor = distanceFromAnchor(position);
      // Indoor GNSS jumps tens of metres without the phone moving. A jump
      // smaller than the reported uncertainty is treated as noise so a
      // nightstand never looks like a departure.
      final realMove = fromAnchor != null &&
          fromAnchor > position.accuracy &&
          fromAnchor > 0;

      if (resting) {
        if (realMove && fromAnchor >= AppConfig.stationaryExitMeters) {
          resetStillAnchor(position);
          await wakeFromRest();
        }
        return;
      }

      if (fromAnchor == null ||
          (realMove && fromAnchor > AppConfig.stationaryRadiusMeters)) {
        resetStillAnchor(position);
        return;
      }

      if (stillSince != null &&
          DateTime.now().difference(stillSince!).inSeconds >=
              AppConfig.stationaryAfterSeconds) {
        await enterRest();
      }
    };

    writePresence = () async {
      final uid = userId;
      if (uid == null || uid.isEmpty) return;
      if (lastPresenceWrite != null &&
          DateTime.now().difference(lastPresenceWrite!).inSeconds < 240) {
        return;
      }
      try {
        await database.ref('presence/$uid').set({
          'online': true,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'appState': appVisible ? 'foreground' : 'background',
        });
        await configurePresenceOnDisconnect(uid);
        lastPresenceWrite = DateTime.now();
      } catch (e) {
        await log('presence_failed', error: e);
      }
    };

    LocationAccuracy movingAccuracy() {
      if (sosMode) return LocationAccuracy.high;
      if (trackingIntervalSeconds <= AppConfig.drivingIntervalSeconds) {
        return LocationAccuracy.high;
      }
      return LocationAccuracy.medium;
    }

    subscribeToPositions = ({bool force = false}) async {
      if (resting && !sosMode) return;

      final accuracy = movingAccuracy();
      if (!force &&
          subscribedIntervalSeconds == trackingIntervalSeconds &&
          subscribedAccuracy == accuracy) {
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await log('permission_denied', error: 'Location permission: $permission');
        setNotification('Location permission needed');
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        await log('location_services_off');
        setNotification('Turn on location services');
        return;
      }

      await positionSubscription?.cancel();
      subscribedIntervalSeconds = trackingIntervalSeconds;
      subscribedAccuracy = accuracy;

      positionSubscription = Geolocator.getPositionStream(
        locationSettings: buildSettings(
          accuracy: accuracy,
          intervalSeconds: trackingIntervalSeconds,
          distanceFilter: AppConfig.publishMinDistanceMeters,
        ),
      ).listen(
        (position) => handlePosition(position),
        onError: (Object e) {
          // Surface the failure instead of hiding it; the watchdog will retry.
          log('position_stream_error', error: e);
          subscribedIntervalSeconds = -1;
          subscribedAccuracy = null;
        },
        cancelOnError: false,
      );

      await log('tracking');
    };

    await reloadIdentity();
    if (userId != null && userId!.isNotEmpty) {
      await configurePresenceOnDisconnect(userId!);
    }

    setNotification(userId != null && userId!.isNotEmpty
        ? 'Location sharing is active'
        : 'Waiting for sign in...');

    // Seed from the last known fix so members are placed immediately instead of
    // waiting out the first GPS acquisition.
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        lastLat = lastKnown.latitude;
        lastLng = lastKnown.longitude;
      }
    } catch (_) {}

    // Resume the cheap regime if we were still when the process last died,
    // so a vendor-cleaner restart does not immediately turn GPS back on.
    final savedMode = store.getString(BgPrefsKeys.mode);
    final savedPush =
        DateTime.tryParse(store.getString(BgPrefsKeys.lastPush) ?? '');
    final recentlyPublished = savedPush != null &&
        DateTime.now().difference(savedPush).inMinutes < 15;
    if (savedMode == 'resting' &&
        recentlyPublished &&
        lastLat != null &&
        lastLng != null) {
      stillAnchorLat = lastLat;
      stillAnchorLng = lastLng;
      stillSince = savedPush;
      await enterRest();
      await restHeartbeat();
    } else {
      await subscribeToPositions(force: true);
    }

    // ─── Commands from the UI isolate ───
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((_) => service.setAsForegroundService());
      service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
    }

    service.on('stopService').listen((_) async {
      restTimer?.cancel();
      restTimer = null;
      await positionSubscription?.cancel();
      final uid = userId;
      if (uid != null && uid.isNotEmpty) {
        try {
          await database.ref('presence/$uid').set({
            'online': false,
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
            'appState': 'stopped',
          });
          await database.ref('presence/$uid').onDisconnect().cancel();
        } catch (_) {}
        presenceRegisteredUserId = null;
      }
      await log('stopped');
      service.stopSelf();
    });

    service.on('setUserId').listen((event) async {
      final incoming = event?['userId'] as String?;
      if (incoming == null || incoming.isEmpty) {
        final prev = presenceRegisteredUserId;
        if (prev != null) {
          try {
            await database.ref('presence/$prev').set({
              'online': false,
              'lastSeen': DateTime.now().millisecondsSinceEpoch,
              'appState': 'signed_out',
            });
            await database.ref('presence/$prev').onDisconnect().cancel();
          } catch (_) {}
          presenceRegisteredUserId = null;
        }
        userId = null;
        // Drop cached identity so a new sign-in cannot inherit it.
        lastLat = null;
        lastLng = null;
        lastAddress = null;
        try {
          await store.remove(BgPrefsKeys.userId);
        } catch (_) {}
      } else {
        userId = incoming;
        try {
          await store.setString(BgPrefsKeys.userId, incoming);
        } catch (_) {}
        await configurePresenceOnDisconnect(incoming);
      }
    });

    service.on('setFamilyIds').listen((event) async {
      final raw = event?['familyIds'];
      familyIds = raw is List
          ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      activeFamilyId = event?['activeFamilyId'] as String?;
      sharingByFamily.clear();
      try {
        await store
            .setString(BgPrefsKeys.familyIds, familyIds.join(','));
        await store
            .setString(BgPrefsKeys.activeFamilyId, activeFamilyId ?? '');
      } catch (_) {}
      // A nest change must not keep publishing to the previous nest's key.
      await log('families_updated');
    });

    service.on('setLocationSharing').listen((event) async {
      final targetFamilyId = event?['familyId'] as String?;
      final enabled = event?['enabled'] as bool? ?? true;
      if (targetFamilyId == null || targetFamilyId.isEmpty) return;
      sharingByFamily[targetFamilyId] = enabled;
      try {
        await store
            .setBool(BgPrefsKeys.sharingEnabled(targetFamilyId), enabled);
      } catch (_) {}
      if (!enabled) {
        // Mark the member inactive so the map stops showing a live position.
        final uid = userId;
        if (uid != null && uid.isNotEmpty) {
          try {
            await database
                .ref('locations/$targetFamilyId/$uid')
                .update({'isActive': false});
          } catch (_) {}
        }
      }
    });

    service.on('setInterval').listen((event) async {
      trackingIntervalSeconds =
          event?['seconds'] ?? AppConfig.locationUpdateIntervalSeconds;
      await subscribeToPositions();
    });

    service.on('setAppVisible').listen((event) {
      appVisible = event?['visible'] as bool? ?? false;
    });

    service.on('forceUpdate').listen((_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: buildSettings(
            accuracy: sosMode
                ? LocationAccuracy.high
                : resting
                    ? LocationAccuracy.low
                    : LocationAccuracy.medium,
            intervalSeconds: 5,
          ),
        ).timeout(Duration(seconds: resting ? 8 : 15));
        await handlePosition(position, force: true);
      } catch (e) {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            await handlePosition(last, force: true);
            return;
          }
        } catch (_) {}
        await log('force_update_failed', error: e);
      }
    });

    service.on('enableSOSMode').listen((_) async {
      sosMode = true;
      trackingIntervalSeconds = AppConfig.sosTrackingIntervalSeconds;
      if (resting) await wakeFromRest();
      await subscribeToPositions(force: true);
      setNotification('Emergency mode - sharing live location');
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: buildSettings(
            accuracy: LocationAccuracy.high,
            intervalSeconds: 1,
          ),
        ).timeout(const Duration(seconds: 20));
        await handlePosition(position, force: true);
      } catch (e) {
        await log('sos_initial_fix_failed', error: e);
      }
    });

    service.on('disableSOSMode').listen((_) async {
      sosMode = false;
      trackingIntervalSeconds = AppConfig.locationUpdateIntervalSeconds;
      await subscribeToPositions();
      setNotification('Location sharing is active');
    });

    // ════════════════════════════════════════════════════════════════════════
    // WATCHDOG — presence plus recovery when the *moving* GPS stream stalls.
    //
    // Resting is not a stall: the radio is off on purpose. Hunting for a
    // high-accuracy fix every couple of minutes indoors is what used to burn
    // the battery all night. Presence is also throttled; a write every minute
    // kept the radio awake for no benefit.
    // ════════════════════════════════════════════════════════════════════════
    Timer.periodic(const Duration(seconds: 90), (timer) async {
      await reloadIdentity();

      final uid = userId;
      if (uid == null || uid.isEmpty) {
        setNotification('Waiting for sign in...');
        await log('no_user');
        return;
      }

      await writePresence();

      if (targetFamilies().isEmpty) {
        setNotification('Location sharing is paused');
        await log('sharing_disabled');
        return;
      }

      if (resting) {
        if (restTimer == null || restTimer!.isActive == false) {
          scheduleRestHeartbeat();
        }
        return;
      }

      setNotification('Location sharing is active');

      final now = DateTime.now();
      final staleFor = lastFixTime == null
          ? now.difference(DateTime.fromMillisecondsSinceEpoch(
              store.getInt('bg_service_started_at') ??
                  now.millisecondsSinceEpoch))
          : now.difference(lastFixTime!);

      if (staleFor.inSeconds < AppConfig.watchdogStaleSeconds) return;
      if (lastStallRecovery != null &&
          now.difference(lastStallRecovery!).inSeconds <
              AppConfig.stallRecoveryCooldownSeconds) {
        return;
      }
      lastStallRecovery = now;

      await log('stream_stalled');
      await subscribeToPositions(force: true);
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          await handlePosition(last, force: true);
          return;
        }
      } catch (_) {}
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: buildSettings(
            accuracy: LocationAccuracy.medium,
            intervalSeconds: 5,
          ),
        ).timeout(const Duration(seconds: 10));
        await handlePosition(position, force: true);
      } catch (e) {
        await log('watchdog_fix_failed', error: e);
      }
    });

    try {
      await prefs.setInt(
          'bg_service_started_at', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}

    // ─── Flush the offline queue when connectivity returns ───
    connectivity.onConnectivityChanged.listen((result) async {
      final isOnline = result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile);
      final uid = userId;
      if (!isOnline || uid == null || uid.isEmpty) return;

      try {
        final cache = LocationCacheService();
        if (await cache.getPendingCount() == 0) return;

        // Guard against replaying a stale queue over a newer live position:
        // that used to teleport members back to where they were hours ago.
        final freshestByFamily = <String, int>{};

        while (true) {
          final batch = await cache.getPendingLocations();
          if (batch.isEmpty) break;

          final syncedIds = <int>[];
          var aborted = false;

          for (final row in batch) {
            final familyId = row['family_id'] as String;
            final rowUser = row['user_id'] as String;
            final rowTimestamp = (row['timestamp'] as num?)?.toInt() ?? 0;

            try {
              var remoteTimestamp = freshestByFamily[familyId];
              if (remoteTimestamp == null) {
                final snapshot = await database
                    .ref('locations/$familyId/$rowUser/timestamp')
                    .get();
                remoteTimestamp = (snapshot.value as num?)?.toInt() ?? 0;
                freshestByFamily[familyId] = remoteTimestamp;
              }

              if (rowTimestamp > remoteTimestamp) {
                final data = cache.rowToLocationData(row);
                await database.ref('locations/$familyId/$rowUser').set(data);
                freshestByFamily[familyId] = rowTimestamp;
              }

              // History is append-only, so a late arrival is always welcome,
              // but it gets the same precision bar as a live write.
              final rowData = cache.rowToLocationData(row);
              final rowAccuracy = (rowData['accuracy'] as num?)?.toDouble();
              if (rowAccuracy == null ||
                  rowAccuracy <= AppConfig.historyMaxAccuracyMeters) {
                final ts = DateTime.fromMillisecondsSinceEpoch(rowTimestamp);
                final dateKey = '${ts.year}-'
                    '${ts.month.toString().padLeft(2, '0')}-'
                    '${ts.day.toString().padLeft(2, '0')}';
                await database
                    .ref(
                        'locationHistory/$familyId/$rowUser/$dateKey/$rowTimestamp')
                    .set(rowData);
              }

              syncedIds.add(row['id'] as int);
            } catch (e) {
              await log('cache_sync_failed', error: e);
              aborted = true;
              break;
            }
          }

          if (syncedIds.isNotEmpty) await cache.markAsSynced(syncedIds);
          // Stop when the batch could not be fully drained, otherwise the
          // outer loop would spin forever on the same failing rows.
          if (aborted || syncedIds.length < batch.length) break;
        }
      } catch (e) {
        await log('cache_flush_failed', error: e);
      }
    });
  } catch (e, st) {
    debugPrint('BackgroundLocationService crashed: $e\n$st');
    try {
      prefs ??= await SharedPreferences.getInstance();
      await prefs.setString(BgPrefsKeys.status, 'CRASHED');
      await prefs.setString(BgPrefsKeys.lastError, e.toString());
    } catch (_) {}
  }
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Battery-optimized tracking strategy
class BatteryOptimizedTracker {
  double _lastSpeed = 0;

  /// Calculate optimal tracking interval based on speed
  int calculateOptimalInterval(double currentSpeed) {
    _lastSpeed = currentSpeed;

    if (currentSpeed < AppConfig.movementThresholdMps) {
      return AppConfig.stationaryIntervalSeconds; // 60s
    }
    if (currentSpeed < 2) {
      return AppConfig.walkingIntervalSeconds; // 30s
    }
    if (currentSpeed < 15) {
      return 20; // Running or cycling
    }
    return AppConfig.drivingIntervalSeconds; // 10s
  }

  /// Get movement status description
  String getMovementStatus() {
    if (_lastSpeed < AppConfig.movementThresholdMps) return 'Stationary';
    if (_lastSpeed < 2) return 'Walking';
    if (_lastSpeed < 5) return 'Running';
    if (_lastSpeed < 15) return 'Cycling';
    return 'Driving';
  }
}

/// Location permission helper.
///
/// Backed by `geolocator` so the same checks give identical answers in the UI
/// isolate and the background isolate.
class LocationPermissionHelper {
  /// Request foreground location permission, prompting for location services
  /// first if they are switched off.
  static Future<bool> requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      if (!await Geolocator.isLocationServiceEnabled()) return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Request "allow all the time", which Android requires as a second,
  /// separate prompt after foreground access has been granted.
  static Future<bool> requestBackgroundPermission() async {
    if (!await requestPermissions()) return false;
    if (await hasBackgroundPermission()) return true;
    final status = await permission_handler.Permission.locationAlways.request();
    return status.isGranted;
  }

  /// Check if we have at least foreground location permission
  static Future<bool> hasAllPermissions() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Check if we have background ("always") location permission
  static Future<bool> hasBackgroundPermission() async {
    return await Geolocator.checkPermission() == LocationPermission.always;
  }

  static Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// Open location settings
  static Future<bool> openLocationSettings() async {
    if (await Geolocator.isLocationServiceEnabled()) return true;
    await Geolocator.openLocationSettings();
    return Geolocator.isLocationServiceEnabled();
  }

  /// Open app settings
  static Future<bool> openAppSettings() =>
      permission_handler.openAppSettings();

  /// Distance in meters between two coordinates.
  static double distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
}

/// Kept for callers that need a Haversine distance without geolocator.
double haversineDistanceMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadius = 6371000.0;
  double toRadians(double degrees) => degrees * math.pi / 180;
  final dLat = toRadians(lat2 - lat1);
  final dLon = toRadians(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRadians(lat1)) *
          math.cos(toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
