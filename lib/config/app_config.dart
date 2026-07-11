// App Configuration
class AppConfig {
  static const String appName = 'FamilyNest';
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
  
  // SOS settings
  static const int sosTrackingIntervalSeconds = 5;
  
  // Family settings
  static const int maxFreeFamilyMembers = 5;
  static const int maxPremiumFamilyMembers = 20;
  
  // Offline cache settings
  static const int maxCachedLocations = 1000;
  static const int offlineBatchUploadSize = 50;
  static const int cachedLocationRetentionDays = 7;
}
