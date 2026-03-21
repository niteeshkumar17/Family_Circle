import 'package:flutter/material.dart';
import '../presentation/screens/splash/splash_screen.dart';
import '../presentation/screens/onboarding/onboarding_screen.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/permissions_screen.dart';
import '../presentation/screens/auth/profile_setup_screen.dart';
import '../presentation/screens/family/create_join_family_screen.dart';
import '../presentation/screens/family/create_family_screen.dart';
import '../presentation/screens/family/join_family_screen.dart';
import '../presentation/screens/home/home_screen.dart';
import '../presentation/screens/sos/sos_screen.dart';
import '../presentation/screens/family/manage_nest_screen.dart';
// Placeholder imports
import '../presentation/screens/placeholder_screens.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String permissions = '/permissions';
  static const String profileSetup = '/profile-setup';
  static const String createJoinFamily = '/create-join-family';
  static const String createFamily = '/create-family';
  static const String joinFamily = '/join-family';
  static const String home = '/home';
  static const String map = '/map';
  static const String family = '/family';
  static const String memberDetail = '/member-detail';
  static const String history = '/history';
  static const String geofence = '/geofence';
  static const String createGeofence = '/create-geofence';
  static const String sos = '/sos';
  static const String manageNest = '/manage-nest';
  static const String settings = '/settings';
  static const String privacy = '/privacy';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _buildRoute(const SplashScreen());
      case onboarding:
        return _buildRoute(const OnboardingScreen());
      case login:
        return _buildRoute(const LoginScreen());
      case permissions:
        return _buildRoute(const PermissionsScreen());
      case profileSetup:
        return _buildRoute(const ProfileSetupScreen());
      case createJoinFamily:
        return _buildRoute(const CreateJoinFamilyScreen());
      case createFamily:
        return _buildRoute(const CreateFamilyScreen());
      case joinFamily:
        return _buildRoute(const JoinFamilyScreen());
      case home:
        return _buildRoute(const HomeScreen());
      case map:
        return _buildRoute(const MapScreen());
      case family:
        return _buildRoute(const FamilyScreen());
      case memberDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return _buildRoute(MemberDetailScreen(
          memberId: args['memberId'],
          memberName: args['memberName'],
          status: args['status'],
          battery: args['battery'],
          lat: args['lat'],
          lng: args['lng'],
        ));
      case history:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildRoute(HistoryScreen(userId: args?['userId']));
      case geofence:
        return _buildRoute(const GeofenceScreen());
      case createGeofence:
        return _buildRoute(const CreateGeofenceScreen());
      case sos:
        return _buildRoute(const SosScreen());
      case manageNest:
        return _buildRoute(const ManageNestScreen());
      case AppRoutes.settings:
        return _buildRoute(const SettingsScreen());
      default:
        return _buildRoute(const SplashScreen());
    }
  }

  static PageRouteBuilder _buildRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}

