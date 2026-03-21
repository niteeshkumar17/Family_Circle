import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/routes.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Know your people better!',
      description: 'Checkout the weather, distance, address and daily whereabouts of people that matter to you',
      icon: Icons.phone_android_rounded,
      iconColor: const Color(0xFF6B8DD6),
    ),
    OnboardingData(
      title: 'Family map, chat and more...',
      description: 'See everyone in a common map and know how far they are from you, reach them, chat with them individually or with everyone together and much more!',
      icon: Icons.map_rounded,
      iconColor: const Color(0xFF8B6DD6),
    ),
    OnboardingData(
      title: 'Have peace of mind!',
      description: 'Get notified when your children/family enters or leaves a place, features like realtime track and navigate to member',
      icon: Icons.self_improvement_rounded,
      iconColor: const Color(0xFF6BD6C3),
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skip() {
    _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Family Nest',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 4),
                  Text(
                    'Specially carved for your social needs!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                ],
              ),
            ),
            
            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),
            
            // Bottom Navigation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF4169E1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Skip Button
                    TextButton(
                      onPressed: _currentPage < _pages.length - 1 ? _skip : null,
                      child: Text(
                        'SKIP',
                        style: TextStyle(
                          color: _currentPage < _pages.length - 1 
                              ? Colors.white 
                              : Colors.transparent,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    
                    // Page Indicators
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 10 : 8,
                          height: _currentPage == index ? 10 : 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index 
                                ? Colors.white 
                                : Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ),
                    
                    // Next/Done Button
                    _currentPage < _pages.length - 1
                        ? IconButton(
                            onPressed: _nextPage,
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          )
                        : TextButton(
                            onPressed: _nextPage,
                            child: const Text(
                              'DONE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 1),
          
          // Title
          Text(
            data.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 400.ms),
          
          const SizedBox(height: 40),
          
          // Illustration
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: data.iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background decorations
                Positioned(
                  top: 20,
                  right: 30,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: data.iconColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 20,
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: data.iconColor.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Main icon
                Icon(
                  data.icon,
                  size: 80,
                  color: data.iconColor,
                ),
              ],
            ),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          
          const SizedBox(height: 40),
          
          // Description
          Text(
            data.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
          
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;

  OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });
}
