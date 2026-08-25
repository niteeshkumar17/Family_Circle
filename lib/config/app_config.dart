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
  static const int historyMaxIntervalSeconds = 300;

  /// A publish is skipped when the device has not moved further than this and
  /// the previous publish is still recent, to avoid burning quota on GPS jitter.
  static const double publishMinDistanceMeters = 15;

  /// Upper bound on how long a member may go without any published update
  /// before the watchdog forces a one-shot GPS read.
  static const int watchdogStaleSeconds = 150;
  
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
