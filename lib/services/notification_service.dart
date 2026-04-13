import 'dart:async';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Notification Service
/// 
/// Handles FCM notifications, local notifications, and notification channels
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;
  StreamSubscription? _tokenRefreshSubscription;
  StreamSubscription<User?>? _authStateSubscription;

  /// Get FCM token
  String? get fcmToken => _fcmToken;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Request permission
    await _requestPermission();

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Get FCM token
    _fcmToken = await _fcm.getToken();

    // Listen for token refresh
    _tokenRefreshSubscription = _fcm.onTokenRefresh.listen((token) async {
      _fcmToken = token;
      await _updateTokenInFirestore(token);
    });

    // Sync existing token when a user signs in after initialization.
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null && _fcmToken != null) {
        await _updateTokenInFirestore(_fcmToken!);
      }
    });
    
    // Update initial token in Firestore
    if (_fcmToken != null) {
      await _updateTokenInFirestore(_fcmToken!);
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background/terminated messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check for initial message (app opened from terminated state)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    _isInitialized = true;
  }

  /// Update FCM token in Firestore for the current user
  Future<void> _updateTokenInFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'deviceInfo': {
            'fcmToken': token,
            'platform': _platformName(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  /// Request notification permission
  Future<bool> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: true, // For SOS
      provisional: false,
      sound: true,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels (Android)
    await _createNotificationChannels();
  }

  /// Create Android notification channels
  Future<void> _createNotificationChannels() async {
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return;

    // SOS Channel - High priority with custom sound
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'sos_alerts',
        'SOS Alerts',
        description: 'Emergency SOS notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color.fromARGB(255, 255, 0, 0),
      ),
    );

    // Geofence Channel
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'geofence_alerts',
        'Location Alerts',
        description: 'Arrival and departure notifications',
        importance: Importance.high,
        playSound: true,
      ),
    );

    // System Alerts Channel
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'system_alerts',
        'System Alerts',
        description: 'Battery and connectivity alerts',
        importance: Importance.defaultImportance,
      ),
    );

    // Family Updates Channel
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'family_updates',
        'Family Updates',
        description: 'Member join/leave notifications',
        importance: Importance.defaultImportance,
      ),
    );

    // General Channel
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'general',
        'General',
        description: 'General notifications',
        importance: Importance.low,
      ),
    );

    // Location Service Channel (for foreground service)
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'family_nest_location',
        'Location Service',
        description: 'Background location tracking',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  /// Handle foreground FCM messages
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;

    if (notification == null) return;

    // Determine notification type and channel
    final type = data['type'] ?? 'general';
    String channelId = 'general';
    Importance importance = Importance.defaultImportance;

    if (type == 'sos') {
      channelId = 'sos_alerts';
      importance = Importance.max;
    } else if (type == 'geofenceEntry' || type == 'geofenceExit') {
      channelId = 'geofence_alerts';
      importance = Importance.high;
    } else if (type == 'lowBattery' || type == 'phoneOff') {
      channelId = 'system_alerts';
    } else if (type == 'familyJoin' || type == 'familyLeave') {
      channelId = 'family_updates';
    }

    // Show local notification
    _showLocalNotification(
      title: notification.title ?? 'FamilyNest',
      body: notification.body ?? '',
      channelId: channelId,
      importance: importance,
      payload: data.toString(),
    );
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];

    // Navigation will be handled through the notification payload
    // The app will check for notification data when opening
    debugPrint('Notification tapped: type=$type, data=$data');
    _pendingNotificationData = data;
  }
  
  // Store pending notification data for the app to handle
  Map<String, dynamic>? _pendingNotificationData;
  
  /// Get and clear pending notification data
  Map<String, dynamic>? consumePendingNotification() {
    final data = _pendingNotificationData;
    _pendingNotificationData = null;
    return data;
  }

  /// Handle local notification tap
  void _onNotificationTap(NotificationResponse response) {
    // Parse payload and handle navigation
    debugPrint('Local notification tapped: ${response.payload}');
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String channelId,
    Importance importance = Importance.defaultImportance,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId,
      importance: importance,
      priority: importance == Importance.max ? Priority.max : Priority.defaultPriority,
      showWhen: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Show SOS notification
  Future<void> showSOSNotification({
    required String userName,
    required String eventId,
    required double latitude,
    required double longitude,
  }) async {
    await _showLocalNotification(
      title: '🚨 SOS EMERGENCY',
      body: '$userName needs help!',
      channelId: 'sos_alerts',
      importance: Importance.max,
      payload: 'sos:$eventId:$latitude:$longitude',
    );
  }

  /// Show geofence notification
  Future<void> showGeofenceNotification({
    required String userName,
    required String placeName,
    required bool isEntry,
  }) async {
    final action = isEntry ? 'arrived at' : 'left';
    await _showLocalNotification(
      title: isEntry ? '📍 Arrival' : '🚶 Departure',
      body: '$userName $action $placeName',
      channelId: 'geofence_alerts',
      importance: Importance.high,
    );
  }

  /// Show low battery notification
  Future<void> showLowBatteryNotification({
    required String userName,
    required int batteryLevel,
  }) async {
    await _showLocalNotification(
      title: '🔋 Low Battery Alert',
      body: '$userName\'s phone is at $batteryLevel%',
      channelId: 'system_alerts',
    );
  }

  /// Subscribe to family topic
  Future<void> subscribeToFamily(String familyId) async {
    await _fcm.subscribeToTopic('family_$familyId');
  }

  /// Unsubscribe from family topic
  Future<void> unsubscribeFromFamily(String familyId) async {
    await _fcm.unsubscribeFromTopic('family_$familyId');
  }

  /// Dispose
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _authStateSubscription?.cancel();
  }

  String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background message
  // For SOS, this should trigger a high-priority notification
  final data = message.data;
  final type = data['type'];

  if (type == 'sos') {
    // SOS notification will be handled by the system
    // The notification payload should already be configured for high priority
  }
}


