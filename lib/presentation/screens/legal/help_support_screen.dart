import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const String _appName = 'Flockar';
  static const String _supportEmail = 'support@niteeshkumar.online';
  static const String _supportPhone = '1800-123-4567';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF00B894),
                    const Color(0xFF00B894).withOpacity(0.8),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.support_agent_rounded, color: Colors.white, size: 40),
                  const SizedBox(height: 14),
                  const Text(
                    'How can we help?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse through our help topics below, or reach out to our support team directly.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Contact Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickContactCard(
                          context,
                          icon: Icons.email_rounded,
                          label: 'Email Us',
                          value: _supportEmail,
                          color: const Color(0xFF4285F4),
                          onTap: () => _launchUrl('mailto:$_supportEmail'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickContactCard(
                          context,
                          icon: Icons.phone_rounded,
                          label: 'Call Us',
                          value: _supportPhone,
                          color: const Color(0xFF00B894),
                          onTap: () => _launchUrl('tel:$_supportPhone'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // FAQ Section Header
                  const Text(
                    'Frequently Asked Questions',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // FAQ - Getting Started
                  _buildFAQCategory(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'Getting Started',
                    color: const Color(0xFF4285F4),
                    questions: [
                      _FAQItem(
                        question: 'How do I create a Nest?',
                        answer: 'After signing in, tap "Create a Nest" on the family setup screen. '
                            'Give your Nest a name (e.g., "Kumar Family") and an invite code will be automatically generated. '
                            'Share this code with family members so they can join your Nest.',
                      ),
                      _FAQItem(
                        question: 'How do I join an existing Nest?',
                        answer: 'Tap "Join a Nest" on the family setup screen or from the Settings menu. '
                            'Enter the invite code shared by your family member and tap "Join". '
                            'You will immediately be added to the Nest and can see all members\' locations.',
                      ),
                      _FAQItem(
                        question: 'Can I be part of multiple Nests?',
                        answer: 'Yes! You can create or join multiple Nests. For example, you might have one Nest for your immediate family '
                            'and another for extended relatives. You can manage location sharing independently for each Nest.',
                      ),
                    ],
                  ),

                  // FAQ - Location
                  _buildFAQCategory(
                    icon: Icons.location_on_rounded,
                    title: 'Location & Tracking',
                    color: const Color(0xFFEA4335),
                    questions: [
                      _FAQItem(
                        question: 'Why is my location not updating?',
                        answer: 'Ensure the following:\n'
                            '• Location services are turned ON in your device settings.\n'
                            '• $_appName has "Allow all the time" location permission.\n'
                            '• Battery optimisation is DISABLED for $_appName (this prevents Android from killing the background service).\n'
                            '• Location sharing is enabled in your Nest settings (Manage Nest).\n'
                            '• You have an active internet connection.',
                      ),
                      _FAQItem(
                        question: 'How accurate is the location?',
                        answer: 'Location accuracy depends on your device\'s GPS hardware and environment. '
                            'In open areas with clear sky, accuracy is typically 3–10 metres. Indoors or in dense urban areas, '
                            'accuracy may decrease to 20–50 metres. The accuracy value is displayed alongside each location update.',
                      ),
                      _FAQItem(
                        question: 'How do I stop sharing my location?',
                        answer: 'Go to the "Settings" tab, then "Manage Nest". You can toggle location sharing off for individual Nests. '
                            'Alternatively, you can disable location permissions for $_appName in your device settings, '
                            'though this will affect all Nests.',
                      ),
                      _FAQItem(
                        question: 'Does location tracking drain my battery?',
                        answer: '$_appName uses a battery-optimised tracking algorithm that adjusts update frequency based on your movement speed. '
                            'When you stop moving for a few minutes the GPS radio is turned off and the app only takes a cheap Wi‑Fi/cell check every few minutes. '
                            'Typical overnight drain is a few percent, not tens of percent. '
                      ),
                    ],
                  ),

                  // FAQ - Places & Geofences
                  _buildFAQCategory(
                    icon: Icons.place_rounded,
                    title: 'Places & Geofences',
                    color: const Color(0xFFFBAE17),
                    questions: [
                      _FAQItem(
                        question: 'What is a geofence?',
                        answer: 'A geofence is a virtual boundary around a real-world location (like Home, School, or Office). '
                            'When a family member enters or leaves a geofenced area, all Nest members receive a notification. '
                            'This helps you stay informed about your family\'s arrivals and departures.',
                      ),
                      _FAQItem(
                        question: 'How do I create a geofence?',
                        answer: 'Go to the "Places" tab on the home screen. Tap "Create Geofence", place the pin on the map, '
                            'give it a name, and adjust the radius using the slider. Tap "Create Geofence" to save.',
                      ),
                      _FAQItem(
                        question: 'Why am I not receiving geofence alerts?',
                        answer: 'Check that:\n'
                            '• Notifications are enabled for $_appName in device settings.\n'
                            '• The geofence is marked as active.\n'
                            '• The family member\'s location is being tracked (their location sharing must be ON).\n'
                            '• Battery saver mode is not restricting background notifications.',
                      ),
                    ],
                  ),

                  // FAQ - SOS & Safety
                  _buildFAQCategory(
                    icon: Icons.emergency_rounded,
                    title: 'SOS & Safety',
                    color: const Color(0xFFE74C3C),
                    questions: [
                      _FAQItem(
                        question: 'How does the SOS feature work?',
                        answer: 'Long-press the SOS button on the home screen. This immediately sends a high-priority alert to all '
                            'members of your active Nest with your precise location. During SOS mode, location updates are sent '
                            'every 5 seconds for maximum accuracy.',
                      ),
                      _FAQItem(
                        question: 'Is SOS a substitute for emergency services?',
                        answer: 'No. The SOS feature is designed to quickly alert your family members. In an emergency, '
                            'always call your local emergency number (112 in India, 911 in the US) first. $_appName is a supplementary '
                            'safety tool and does not replace emergency services.',
                      ),
                    ],
                  ),

                  // FAQ - Account & Privacy
                  _buildFAQCategory(
                    icon: Icons.shield_rounded,
                    title: 'Account & Privacy',
                    color: const Color(0xFF6C63FF),
                    questions: [
                      _FAQItem(
                        question: 'How do I delete my account?',
                        answer: 'To delete your account and all associated data, go to Settings > Account Actions > Contact Support. '
                            'Send an email to $_supportEmail requesting account deletion. '
                            'Your data will be permanently erased within 30 days of the request.',
                      ),
                      _FAQItem(
                        question: 'Who can see my location?',
                        answer: 'Only members of the Nests you belong to can see your location. No one outside your Nest — '
                            'including $_appName staff — can access your real-time location. You control who is in your Nest by managing invites.',
                      ),
                      _FAQItem(
                        question: 'Is my data sold to third parties?',
                        answer: 'Absolutely not. We never sell, rent, or trade your personal data. Your information is used solely '
                            'to provide the $_appName service. Please review our Privacy Policy for full details.',
                      ),
                    ],
                  ),

                  // FAQ - Troubleshooting
                  _buildFAQCategory(
                    icon: Icons.build_circle_rounded,
                    title: 'Troubleshooting',
                    color: const Color(0xFF95A5A6),
                    questions: [
                      _FAQItem(
                        question: 'The app is crashing or freezing',
                        answer: 'Try the following steps:\n'
                            '1. Force-close the app and reopen it.\n'
                            '2. Clear the app cache (Settings > Apps > $_appName > Clear Cache).\n'
                            '3. Ensure you are running the latest version of the app.\n'
                            '4. Restart your device.\n'
                            '5. If the issue persists, contact us at $_supportEmail with your device model and Android version.',
                      ),
                      _FAQItem(
                        question: 'I\'m not receiving any notifications',
                        answer: 'Check these settings:\n'
                            '• Device Settings > Apps > $_appName > Notifications — ensure all categories are enabled.\n'
                            '• Do Not Disturb mode should be off (or $_appName should be excluded).\n'
                            '• Battery optimisation should be disabled for $_appName.\n'
                            '• On some devices (Xiaomi, Huawei, Samsung), check for "Auto-start" or "Background restrictions" in device settings.',
                      ),
                      _FAQItem(
                        question: 'Family members are not visible on the map',
                        answer: 'Ensure that:\n'
                            '• The family member has the app installed and is logged in.\n'
                            '• They have enabled location sharing for the Nest.\n'
                            '• Their device has an active internet connection.\n'
                            '• The background service is running (check for the "Location sharing active" notification).',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Still need help?
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1A1A2E),
                          Color(0xFF16213E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 40),
                        const SizedBox(height: 16),
                        const Text(
                          'Still need help?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Our support team is available Mon–Sat, 9 AM – 7 PM IST.\nWe typically respond within 24 hours.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _launchUrl('mailto:$_supportEmail?subject=Flockar Support Request'),
                                icon: const Icon(Icons.email_rounded, size: 18),
                                label: const Text('Email'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _launchUrl('tel:$_supportPhone'),
                                icon: const Icon(Icons.phone_rounded, size: 18),
                                label: const Text('Call'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00B894),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      '$_appName v1.0.0',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickContactCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQCategory({
    required IconData icon,
    required String title,
    required Color color,
    required List<_FAQItem> questions,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...questions.map((faq) => _FAQTile(faq: faq, accentColor: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _FAQItem {
  final String question;
  final String answer;

  _FAQItem({required this.question, required this.answer});
}

class _FAQTile extends StatefulWidget {
  final _FAQItem faq;
  final Color accentColor;

  const _FAQTile({required this.faq, required this.accentColor});

  @override
  State<_FAQTile> createState() => _FAQTileState();
}

class _FAQTileState extends State<_FAQTile> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.faq.question,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _isExpanded ? FontWeight.w600 : FontWeight.w500,
                      color: _isExpanded ? widget.accentColor : const Color(0xFF2A2A4A),
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _isExpanded ? widget.accentColor : Colors.grey,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.accentColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.faq.answer,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4A4A68),
                  height: 1.6,
                ),
              ),
            ),
          ),
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        if (!_isExpanded) const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }
}
