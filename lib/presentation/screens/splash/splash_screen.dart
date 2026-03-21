import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/routes.dart';
import '../../../config/theme_config.dart';
import '../../../services/background_service.dart';
import '../../../services/notification_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkStatusAndNavigate();
  }

  Future<void> _checkStatusAndNavigate() async {
    // Wait for splash animation
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Check onboarding status
    final prefs = await SharedPreferences.getInstance();
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

    if (!onboardingCompleted) {
      // First time user - show onboarding
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
      return;
    }

    // Check if user is already authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User is logged in, check if they completed all setup steps
      final permissionsCompleted = prefs.getBool('permissions_completed') ?? false;
      
      if (!permissionsCompleted) {
        // User hasn't done permissions - go to permissions screen
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRoutes.permissions);
        return;
      } else {
        // Initialize services if permissions are already granted
        try {
          await NotificationService().initialize();
          await BackgroundLocationService().start();
        } catch (e) {
          debugPrint('Error starting services: $e');
        }
      }

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        final phone = userDoc.data()?['phone']?.toString() ?? '';
        final hasCompletedSetup = userDoc.exists && phone.isNotEmpty;
        
        if (!hasCompletedSetup) {
          // User hasn't completed profile setup
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(AppRoutes.profileSetup);
          return;
        }
        
        // Check if user has joined a family
        final familyIds = List<String>.from(userDoc.data()?['familyIds'] ?? []);
        if (familyIds.isEmpty) {
          // User hasn't joined/created a family yet
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(AppRoutes.createJoinFamily);
          return;
        }
      } catch (e) {
        debugPrint('Error checking user setup: $e');
      }
      
      // User completed everything - go to home
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } else {
      // User is not logged in, navigate to login
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.family_restroom_rounded,
                  size: 70,
                  color: AppTheme.primaryColor,
                ),
              )
                  .animate()
                  .scale(duration: 600.ms, curve: Curves.elasticOut)
                  .fadeIn(duration: 400.ms),
              
              const SizedBox(height: 24),
              
              // App Name
              Text(
                'FamilyNest',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.3, end: 0),
              
              const SizedBox(height: 8),
              
              // Tagline
              Text(
                'Keep your family safe, together',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
              )
                  .animate(delay: 500.ms)
                  .fadeIn(duration: 500.ms),
              
              const SizedBox(height: 60),
              
              // Loading indicator
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  .animate(delay: 700.ms)
                  .fadeIn(duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
