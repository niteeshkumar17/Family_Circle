import 'package:flutter/material.dart';
import '../../../config/theme_config.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _effectiveDate = 'July 11, 2026';
  static const String _appName = 'Flockar';
  static const String _companyName = 'Flockar Technologies';
  static const String _contactEmail = 'legal@flockar.niteeshkumar.online';

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
          'Terms of Service',
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
                    const Color(0xFF6C63FF),
                    const Color(0xFF6C63FF).withOpacity(0.8),
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
                      'Last Updated: $_effectiveDate',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Terms of Service',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please read these terms carefully before using $_appName. By accessing or using our Service, you agree to be bound by these terms.',
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
                    icon: Icons.gavel_rounded,
                    title: '1. Acceptance of Terms',
                    children: [
                      _buildParagraph(
                        'By downloading, installing, or using the $_appName application ("Service") operated by $_companyName ("we", "our", or "us"), '
                        'you ("User", "you", or "your") agree to comply with and be bound by these Terms of Service ("Terms"). '
                        'If you do not agree to all of these Terms, you must not access or use the Service.',
                      ),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        'These Terms constitute a legally binding agreement between you and $_companyName. '
                        'We reserve the right to modify these Terms at any time. Material changes will be communicated via in-app notification at least 14 days prior to taking effect.',
                      ),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.app_registration_rounded,
                    title: '2. Account Registration & Eligibility',
                    children: [
                      _buildBulletList([
                        'You must be at least 13 years of age to create an account. Users under 13 may only use the Service under a parent or guardian\'s account.',
                        'You are responsible for maintaining the confidentiality of your login credentials and for all activities under your account.',
                        'You agree to provide accurate, current, and complete information during registration and to update such information as necessary.',
                        'You must not create accounts using automated means or under false pretences.',
                        'We reserve the right to suspend or terminate any account that violates these Terms.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.thumb_up_alt_rounded,
                    title: '3. Acceptable Use',
                    children: [
                      _buildParagraph('You agree to use $_appName solely for lawful family safety purposes. You shall not:'),
                      const SizedBox(height: 8),
                      _buildBulletList([
                        'Use the Service to track, stalk, or monitor any person without their explicit knowledge and informed consent.',
                        'Add any person to a Nest without their voluntary agreement.',
                        'Use the Service for any commercial, advertising, or promotional purposes.',
                        'Attempt to reverse-engineer, decompile, or disassemble any portion of the Service.',
                        'Interfere with, disrupt, or place an undue burden on the Service\'s servers or network infrastructure.',
                        'Circumvent or manipulate any security, authentication, or access-control mechanisms of the Service.',
                        'Transmit any viruses, malware, or malicious code through the Service.',
                        'Use the Service in any way that violates applicable local, state, national, or international law.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.location_on_rounded,
                    title: '4. Location Services & Consent',
                    children: [
                      _buildBulletList([
                        'The core functionality of $_appName relies on real-time location sharing. By enabling location sharing, you consent to the collection and transmission of your geographic data to members of your Nest.',
                        'Location data is shared exclusively with members of Nests you voluntarily join. You may disable location sharing for any Nest at any time via the "Manage Nest" screen.',
                        'You are solely responsible for obtaining consent from all individuals whose location data is tracked through your account, including minors under your guardianship.',
                        'We are not liable for any disputes arising from the use of location tracking features between Nest members.',
                        'Location accuracy depends on device hardware, network conditions, and environmental factors. We do not guarantee the precision of location data.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.family_restroom_rounded,
                    title: '5. Nests & Family Groups',
                    children: [
                      _buildBulletList([
                        'A "Nest" is a private family group within $_appName. You may create or join multiple Nests.',
                        'The creator of a Nest assumes the role of administrator and is responsible for managing membership and settings.',
                        'Nest administrators may invite or remove members, configure geofences, and manage location sharing preferences for the group.',
                        'Free accounts are limited to ${5} family members per Nest. Premium plans offer expanded capacity.',
                        'You may leave any Nest at any time. Upon leaving, your location data will no longer be visible to that Nest\'s members.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.warning_amber_rounded,
                    title: '6. Emergency & SOS Features',
                    children: [
                      _buildBulletList([
                        '$_appName provides SOS alert features for convenience and supplementary safety. These features are not a substitute for emergency services (such as dialling 112 or local emergency numbers).',
                        'We do not guarantee the delivery, timeliness, or accuracy of SOS alerts. Alert delivery depends on network connectivity, device status, and third-party services.',
                        'You should always contact official emergency services in life-threatening situations. $_appName is not an emergency response service.',
                        'We disclaim all liability for damages or losses arising from reliance on SOS or alert features.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.copyright_rounded,
                    title: '7. Intellectual Property',
                    children: [
                      _buildBulletList([
                        'All content, features, functionality, design elements, trademarks, and logos within $_appName are owned by $_companyName and are protected by applicable intellectual property laws.',
                        'You are granted a limited, non-exclusive, non-transferable, revocable licence to use the Service for personal, non-commercial purposes in accordance with these Terms.',
                        'You may not copy, modify, distribute, sell, or lease any part of the Service or its underlying software without our prior written consent.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.block_rounded,
                    title: '8. Limitation of Liability',
                    children: [
                      _buildParagraph(
                        'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW:',
                      ),
                      const SizedBox(height: 8),
                      _buildBulletList([
                        'THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY.',
                        'WE DISCLAIM ALL WARRANTIES INCLUDING, WITHOUT LIMITATION, WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.',
                        '$_companyName, its officers, directors, employees, and affiliates shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the Service.',
                        'Our total aggregate liability shall not exceed the amount you paid for the Service in the 12 months preceding the claim, or ₹500, whichever is greater.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.cancel_outlined,
                    title: '9. Termination',
                    children: [
                      _buildBulletList([
                        'You may terminate your account at any time by deleting your account through the app or by contacting us at $_contactEmail.',
                        'We may suspend or terminate your access to the Service immediately, without prior notice or liability, for any reason, including if you breach these Terms.',
                        'Upon termination, your right to use the Service ceases immediately. Provisions that by their nature should survive termination (including limitations of liability, indemnification, and dispute resolution) shall survive.',
                        'We will delete your personal data within 30 days of account termination, as outlined in our Privacy Policy.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.balance_rounded,
                    title: '10. Governing Law & Dispute Resolution',
                    children: [
                      _buildBulletList([
                        'These Terms shall be governed by and construed in accordance with the laws of India, without regard to conflict-of-law principles.',
                        'Any disputes arising out of or relating to these Terms or the Service shall first be attempted to be resolved through good-faith negotiation.',
                        'If negotiation fails, disputes shall be submitted to binding arbitration under the Arbitration and Conciliation Act, 1996, conducted in New Delhi, India.',
                        'You agree to waive any right to participate in a class action lawsuit or class-wide arbitration.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.shield_outlined,
                    title: '11. Indemnification',
                    children: [
                      _buildParagraph(
                        'You agree to indemnify, defend, and hold harmless $_companyName and its officers, directors, employees, agents, and affiliates from and against any claims, liabilities, damages, losses, and expenses (including reasonable legal fees) arising out of or in any way connected with:',
                      ),
                      const SizedBox(height: 8),
                      _buildBulletList([
                        'Your use of or inability to use the Service.',
                        'Your violation of these Terms.',
                        'Your violation of any third-party rights, including privacy rights.',
                        'Any content you transmit or share through the Service.',
                      ]),
                    ],
                  ),

                  _buildSection(
                    icon: Icons.mail_outline_rounded,
                    title: '12. Contact Information',
                    children: [
                      _buildParagraph(
                        'For questions or concerns about these Terms of Service, please contact us:',
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
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
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
              decoration: const BoxDecoration(
                color: Color(0xFF6C63FF),
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
        color: const Color(0xFFF0EEFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.email_outlined, size: 16, color: Color(0xFF6C63FF)),
              SizedBox(width: 8),
              Text(
                _contactEmail,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.language_rounded, size: 16, color: Color(0xFF6C63FF)),
              SizedBox(width: 8),
              Text(
                'https://flockar.niteeshkumar.online/terms',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6C63FF),
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
