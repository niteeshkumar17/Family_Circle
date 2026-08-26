import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'services/notification_service.dart';
import 'services/tracker_watchdog.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D0D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Firebase
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e, st) {
    if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
      debugPrint('Firebase already initialized natively, ignoring duplicate error.');
    } else {
      debugPrint('Firebase initialization failed: $e');
      debugPrintStack(stackTrace: st);
      runApp(FirebaseInitializationErrorApp(error: e.toString()));
      return;
    }
  }

  // Registered here rather than in NotificationService so that a wake-up push
  // can still revive the tracker when the app is launched straight into the
  // background and never reaches permission setup.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Registers the WorkManager callback used to restart the location service
  // after a vendor cleaner kills the process. The job itself is scheduled once
  // the user is in a nest.
  await TrackerWatchdog.initialize();

  // NOTE: NotificationService and BackgroundLocationService are now initialized
  // in the PermissionsScreen AFTER the user grants permissions.
  // This provides a better user experience like professional apps.

  // Run the app
  runApp(const FlockarApp());
}

class FirebaseInitializationErrorApp extends StatelessWidget {
  const FirebaseInitializationErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Unable to start Flockar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Firebase failed to initialize. Please check your network and app configuration, then restart the app.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
