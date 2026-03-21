import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/routes.dart';
import '../../../services/notification_service.dart';
import '../../../services/background_service.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  final List<PermissionItem> _permissions = [
    PermissionItem(
      icon: Icons.notifications_active_rounded,
      title: 'Notifications',
      description: 'Get alerts when family members arrive or leave places, SOS emergencies, and important updates.',
      color: const Color(0xFFFF6B6B),
    ),
    PermissionItem(
      icon: Icons.location_on_rounded,
      title: 'Location Access',
      description: 'Share your location with family members so they know you\'re safe. Works in the background too.',
      color: const Color(0xFF4ECDC4),
    ),
    PermissionItem(
      icon: Icons.battery_saver_rounded,
      title: 'Battery Optimization',
      description: 'Disable battery optimization to ensure location updates work reliably in the background.',
      color: const Color(0xFFFFE66D),
    ),
  ];

  Future<void> _requestCurrentPermission() async {
    setState(() => _isLoading = true);

    try {
      bool granted = false;

      switch (_currentStep) {
        case 0:
          // Request notification permission
          final status = await Permission.notification.request();
          granted = status.isGranted;
          if (granted) {
            // Initialize notification service after permission granted
            try {
              await NotificationService().initialize();
            } catch (e) {
              debugPrint('NotificationService init error: $e');
            }
          }
          break;

        case 1:
          // Request location permission (foreground first)
          PermissionStatus locationStatus = await Permission.location.request();
          if (locationStatus.isGranted) {
            // Request background location
            final bgStatus = await Permission.locationAlways.request();
            granted = bgStatus.isGranted || locationStatus.isGranted;
            
            if (granted) {
              // Initialize background location service
              try {
                await BackgroundLocationService().start();
              } catch (e) {
                debugPrint('BackgroundLocationService init error: $e');
              }
            }
          }
          break;

        case 2:
          // Request to ignore battery optimizations
          final status = await Permission.ignoreBatteryOptimizations.request();
          granted = status.isGranted;
          break;
      }

      if (mounted) {
        if (_currentStep < _permissions.length - 1) {
          setState(() {
            _currentStep++;
            _isLoading = false;
          });
        } else {
          // All permissions done, save flag and navigate to profile setup
          await _completePermissions();
        }
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
      // Continue to next step even if there's an error
      if (mounted) {
        if (_currentStep < _permissions.length - 1) {
          setState(() {
            _currentStep++;
            _isLoading = false;
          });
        } else {
          await _completePermissions();
        }
      }
    }
  }

  void _skipCurrent() {
    if (_currentStep < _permissions.length - 1) {
      setState(() => _currentStep++);
    } else {
      _completePermissions();
    }
  }

  Future<void> _completePermissions() async {
    // Save permissions completed flag
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_completed', true);
    
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.profileSetup);
  }

  @override
  Widget build(BuildContext context) {
    final currentPermission = _permissions[_currentStep];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Progress indicator
              Row(
                children: List.generate(
                  _permissions.length,
                  (index) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: index < _permissions.length - 1 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: index <= _currentStep 
                            ? currentPermission.color 
                            : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 16),

              // Step indicator
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step ${_currentStep + 1} of ${_permissions.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // Permission Icon
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: currentPermission.color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  currentPermission.icon,
                  size: 70,
                  color: currentPermission.color,
                ),
              ).animate(key: ValueKey(_currentStep))
                .scale(duration: 400.ms, curve: Curves.elasticOut),

              const SizedBox(height: 48),

              // Title
              Text(
                currentPermission.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ).animate(key: ValueKey('title_$_currentStep'))
                .fadeIn(duration: 300.ms),

              const SizedBox(height: 16),

              // Description
              Text(
                currentPermission.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate(key: ValueKey('desc_$_currentStep'))
                .fadeIn(duration: 300.ms, delay: 100.ms),

              const Spacer(flex: 2),

              // Allow Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestCurrentPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentPermission.color,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.black.withOpacity(0.6),
                            ),
                          ),
                        )
                      : Text(
                          'Allow ${currentPermission.title}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ).animate(key: ValueKey('btn_$_currentStep'))
                .fadeIn(duration: 300.ms, delay: 200.ms)
                .slideY(begin: 0.1),

              const SizedBox(height: 16),

              // Skip Button
              TextButton(
                onPressed: _isLoading ? null : _skipCurrent,
                child: Text(
                  _currentStep < _permissions.length - 1 ? 'Skip for now' : 'Maybe later',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionItem {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
