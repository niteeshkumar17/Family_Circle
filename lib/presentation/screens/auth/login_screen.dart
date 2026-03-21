import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/theme_config.dart';
import '../../../config/routes.dart';
import '../../blocs/auth/auth_bloc.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _handleAuthSuccess(BuildContext context, AuthAuthenticated state) async {
    // Check if user has completed onboarding by looking at Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(state.user.uid)
        .get();
    
    // Check if user has a profile with phone number (meaning they completed setup)
    final phone = userDoc.data()?['phone']?.toString() ?? '';
    final hasCompletedSetup = userDoc.exists && phone.isNotEmpty;
    
    // Also check if permissions setup was done
    final prefs = await SharedPreferences.getInstance();
    final permissionsCompleted = prefs.getBool('permissions_completed') ?? false;
    
    if (!context.mounted) return;
    
    if (!permissionsCompleted) {
      // User hasn't done permissions - go to permissions screen
      Navigator.of(context).pushReplacementNamed(AppRoutes.permissions);
    } else if (!hasCompletedSetup) {
      // User did permissions but not profile - go to profile setup
      Navigator.of(context).pushReplacementNamed(AppRoutes.profileSetup);
    } else {
      // User completed everything - go to home
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          _handleAuthSuccess(context, state);
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red.shade400,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                
                // App Logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.family_restroom,
                    size: 60,
                    color: Colors.white,
                  ),
                ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
                
                const SizedBox(height: 32),
                
                // Welcome Text
                Text(
                  'Welcome to',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.2),
                
                Text(
                  'FamilyNest',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(begin: 0.2),
                
                const SizedBox(height: 12),
                
                Text(
                  'Keep your family safe and connected',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
                
                const Spacer(flex: 3),
                
                // Google Sign-In Button
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final isLoading = state is AuthLoading;
                    
                    return SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                context.read<AuthBloc>().add(AuthGoogleSignInRequested());
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          elevation: 2,
                          shadowColor: Colors.black.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryColor,
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Google Logo
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'G',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          foreground: Paint()
                                            ..shader = const LinearGradient(
                                              colors: [
                                                Color(0xFF4285F4), // Blue
                                                Color(0xFF34A853), // Green
                                                Color(0xFFFBBC05), // Yellow
                                                Color(0xFFEA4335), // Red
                                              ],
                                            ).createShader(
                                              const Rect.fromLTWH(0, 0, 24, 24),
                                            ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Continue with Google',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 500.ms).slideY(begin: 0.2);
                  },
                ),
                
                const SizedBox(height: 32),
                
                // Terms and Privacy
                Text.rich(
                  TextSpan(
                    text: 'By continuing, you agree to our\n',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.5),
                    ),
                    children: [
                      const TextSpan(
                        text: 'Terms of Service',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(
                        text: ' and ',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                      const TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
