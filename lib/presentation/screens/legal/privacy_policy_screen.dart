import 'package:flutter/material.dart';
import '../../../config/theme_config.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _effectiveDate = 'July 11, 2026';
  static const String _appName = 'Flockar';
  static const String _companyName = 'Flockar Technologies';
  static const String _contactEmail = 'privacy@niteeshkumar.online';

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
          'Privacy Policy',
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
                    AppTheme.primaryColor,
                    AppTheme.primaryColor.withOpacity(0.8),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Effective: $_effectiveDate',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your Privacy Matters',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_appName is committed to protecting your personal information and your right to privacy.',
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
                  _buildSection(
                    icon: Icons.info_outline_rounded,
                    title: '1. Introduction',
                    children: [
                      _buildParagraph(
                        '$_companyName ("we", "our", or "us") operates the $_appName mobile application (the "Service"). '
                        'This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our Service. '
                        'By using $_appName, you consent to the data practices described in this policy.',
                      ),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.data_usage_rounded,
                    title: '2. Information We Collect',
                    children: [
                      _buildSubheading('2.1 Personal Information'),
                      _buildBulletList([
                        'Account credentials (name, email address, profile photo) provided during registration or via Google Sign-In.',
                        'Phone number, if voluntarily provided for SOS and emergency contact features.',
                      ]),
                      const SizedBox(height: 12),
                      _buildSubheading('2.2 Location Data'),
                      _buildBulletList([
                        'Real-time geographic coordinates (latitude, longitude, altitude, speed, heading) collected via device GPS sensors.',
                        'Reverse-geocoded addresses derived from coordinates for display purposes.',
                        'Historical location data retained for up to 30 days to power the location history feature.',
                        'Location data is collected only when you have explicitly enabled location sharing for a given Nest.',
                      ]),
                      const SizedBox(height: 12),
                      _buildSubheading('2.3 Device & Usage Data'),
                      _buildBulletList([
                        'Battery level and charging state, used to display device status to family members and trigger low-battery alerts.',
                        'Network connectivity status (Wi-Fi, cellular, offline).',
                        'App usage analytics such as screen views and feature engagement (anonymised, no personal identifiers).',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.settings_suggest_rounded,
                    title: '3. How We Use Your Information',
                    children: [
                      _buildBulletList([
                        'To display your real-time and historical location to family members you have explicitly invited into your Nest.',
                        'To trigger geofence alerts when family members enter or leave designated safe zones.',
                        'To deliver emergency SOS notifications with your precise location to all Nest members.',
                        'To send low-battery and connectivity-related alerts.',
                        'To provide in-app notifications about family member movements and safety events.',
                        'To maintain, improve, and optimise the performance and security of our Service.',
                        'To comply with applicable legal obligations.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.share_rounded,
                    title: '4. How We Share Your Information',
                    children: [
                      _buildParagraph(
                        'We do not sell, rent, or trade your personal data to any third party. Your information is shared only in the following limited circumstances:',
                      ),
                      const SizedBox(height: 8),
                      _buildBulletList([
                        'With your Nest members: Your location, battery status, and activity data are visible only to members of Nests you belong to.',
                        'With Firebase (Google): We use Google Firebase for authentication, real-time database, cloud storage, and push notifications. Firebase processes your data in accordance with Google\'s privacy policies.',
                        'With law enforcement: We may disclose information if required by law, regulation, legal process, or governmental request.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.storage_rounded,
                    title: '5. Data Retention & Storage',
                    children: [
                      _buildBulletList([
                        'Real-time location data is overwritten with each update and is not retained after your session.',
                        'Location history is stored for a maximum of 30 days and is automatically purged thereafter.',
                        'Your account information is retained for as long as your account remains active.',
                        'Upon account deletion, all personal data (including location history and profile information) is permanently erased from our systems within 30 days.',
                        'All data is stored in Firebase infrastructure protected by Google\'s enterprise-grade security, including AES-256 encryption at rest and TLS 1.3 in transit.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.security_rounded,
                    title: '6. Data Security',
                    children: [
                      _buildParagraph(
                        'We implement industry-standard security measures to protect your data:',
                      ),
                      const SizedBox(height: 8),
                      _buildBulletList([
                        'All data in transit is encrypted using TLS 1.2/1.3.',
                        'Data at rest is encrypted using AES-256 encryption.',
                        'Firebase Authentication secures all account access with OAuth 2.0 tokens.',
                        'Database security rules ensure users can only read and write data they are authorised to access.',
                        'We conduct regular security reviews and vulnerability assessments.',
                      ]),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        'While we take reasonable precautions, no method of electronic transmission or storage is 100% secure. We cannot guarantee absolute data security.',
                      ),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.person_rounded,
                    title: '7. Your Rights & Choices',
                    children: [
                      _buildParagraph('You have the following rights regarding your personal data:'),
                      const SizedBox(height: 8),
                      _buildBulletList([
                        'Access & Portability: You may request a copy of all personal data we hold about you.',
                        'Correction: You may update your profile information at any time through the app.',
                        'Deletion: You may request deletion of your account and all associated data by contacting us.',
                        'Location Control: You can enable or disable location sharing per Nest at any time via the "Manage Nest" screen.',
                        'Notification Control: You can manage push notification preferences through your device settings.',
                        'Withdraw Consent: You may withdraw consent at any time by disabling location services or deleting your account.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.child_care_rounded,
                    title: '8. Children\'s Privacy',
                    children: [
                      _buildParagraph(
                        '$_appName is a family safety application designed to include children within a family unit. '
                        'Accounts for children under the age of 13 must be created and managed by a parent or legal guardian who is a member of the same Nest. '
                        'The parent or guardian assumes full responsibility for the child\'s data and consent. '
                        'We do not knowingly collect information from children under 13 without verifiable parental consent.',
                      ),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.update_rounded,
                    title: '9. Changes to This Policy',
                    children: [
                      _buildParagraph(
                        'We may update this Privacy Policy from time to time. When we make material changes, we will notify you through an in-app notification or via the email associated with your account. '
                        'Continued use of the Service after such notification constitutes your acceptance of the updated policy. '
                        'We encourage you to review this policy periodically.',
                      ),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.mail_outline_rounded,
                    title: '10. Contact Us',
                    children: [
                      _buildParagraph(
                        'If you have questions, concerns, or requests regarding this Privacy Policy or your personal data, please contact us:',
                      ),
                      const SizedBox(height: 12),
                      _buildContactCard(),
                    ],
                  ),

                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      '© 2026 $_companyName. All rights reserved.',
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

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF4A4A68),
        height: 1.6,
      ),
    );
  }

  Widget _buildSubheading(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2A2A4A),
        ),
      ),
    );
  }

  Widget _buildBulletList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4A4A68),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.email_outlined, size: 16, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                _contactEmail,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.language_rounded, size: 16, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                'https://flockar.niteeshkumar.online/privacy',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
