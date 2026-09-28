// App Configuration
class AppConfig {
  static const String appName = 'Flockar';
  static const String appVersion = '1.0.0';
  
  // Location settings
  static const int locationUpdateIntervalSeconds = 15;
  static const int stationaryIntervalSeconds = 60;
  static const int walkingIntervalSeconds = 30;
  static const int drivingIntervalSeconds = 10;
  static const double movementThresholdMps = 0.5;

  // ─── Motion regimes ───
  //
  // The tracker runs in one of two regimes. "Moving" keeps the GPS on at high
  // accuracy. "Resting" turns the GPS off entirely and asks the fused provider
  // for a coarse WiFi/cell fix every few minutes instead, which costs almost
  // nothing and doubles as the wake-up for the "still here" heartbeat. A phone
  // left on a nightstand used to burn ~10% an hour running GPS every 15s; in
  // the resting regime it should be closer to 0.3%.

  /// GPS stream interval while moving. Publishing is throttled separately by
  /// speed, so this only bounds how often the hardware is asked for a fix.
  static const int movingIntervalSeconds = 15;

  /// The user is resting once every fix for [stationaryAfterSeconds] has been
  /// within this distance of the first one.
  static const double stationaryRadiusMeters = 50;
  static const int stationaryAfterSeconds = 180;

  /// Leaving the resting regime needs a larger displacement than entering it
  /// (hysteresis), because a WiFi-only fix can be tens of metres off.
  static const double stationaryExitMeters = 100;

  /// While resting: how often to take a coarse WiFi/cell fix and re-publish the
  /// anchor so the family map and the server-side stale sweep both see a live
  /// device. Must stay well under the server's 20-minute stale window.
  static const int stationaryHeartbeatSeconds = 300;

  /// After this long still, drop to the slower heartbeat. A phone on a
  /// nightstand does not need a fix every five minutes.
  static const int deepRestAfterSeconds = 1200;
  static const int deepRestHeartbeatSeconds = 600;

  /// A member is shown as offline after this long without a presence write.
  /// Must comfortably exceed [deepRestHeartbeatSeconds].
  static const int presenceOfflineAfterMinutes = 15;

  /// Minimum gap between attempts to recover a silent GPS stream. Without this
  /// a phone indoors, where GPS cannot get a fix at all, retried at full power
  /// every minute all night.
  static const int stallRecoveryCooldownSeconds = 300;
  
  // Geofence settings
  static const double defaultGeofenceRadiusMeters = 200;
  static const double minGeofenceRadiusMeters = 50;
  static const double maxGeofenceRadiusMeters = 1000;
  
  // Geofence advanced settings
  static const double geofenceHysteresisMeters = 20.0; // Cushion to prevent boundary flapping
  static const int geofenceDwellTimeSeconds = 180;      // 3 minutes before dwell alert fires
  
  // History settings
  static const int locationHistoryDays = 30;

  /// A history breadcrumb is only recorded once the user has moved at least
  /// this far, or once [historyMaxIntervalSeconds] has elapsed. Without this
  /// throttle a stationary device writes a point on every tick, which bloats
  /// Realtime Database and makes trails unreadable.
  static const double historyMinDistanceMeters = 25;
  static const int historyMaxIntervalSeconds = 900;

  /// Fixes less precise than this are published live but kept out of history.
  /// Resting heartbeats come from WiFi/cell and are routinely 100m+ off, which
  /// used to zigzag a trail around a house all night and inflate the distance.
  static const double historyMaxAccuracyMeters = 100;

  // Timeline reconstruction (history screen).

  /// Points within this distance of a cluster's centre belong to the same stop.
  static const double stayRadiusMeters = 120;

  /// Minimum time at one spot before it counts as a stop rather than traffic.
  static const int stayMinSeconds = 5 * 60;

  /// A silence longer than this between two distant points is shown as missing
  /// data instead of a straight line across the map.
  static const int historyGapSeconds = 20 * 60;

  /// A publish is skipped when the device has not moved further than this and
  /// the previous publish is still recent, to avoid burning quota on GPS jitter.
  static const double publishMinDistanceMeters = 15;

  /// Upper bound on how long the moving-regime GPS stream may stay silent
  /// before the watchdog tries a cheap recovery. Resting is not "stale".
  static const int watchdogStaleSeconds = 180;
  
  // SOS settings
  static const int sosTrackingIntervalSeconds = 5;
  
  // Family settings
  static const int maxFreeFamilyMembers = 5;
  static const int maxPremiumFamilyMembers = 20;
  
  /// Key used for the Directions API when drawing in-app route previews.
  /// Override per build with --dart-define=GOOGLE_MAPS_API_KEY=...
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyCJmFTrE-O6VZSkYthgej0uHr_Cg-jfYuE',
  );

  // Offline cache settings
  static const int maxCachedLocations = 1000;
  static const int offlineBatchUploadSize = 50;
  static const int cachedLocationRetentionDays = 7;
}
