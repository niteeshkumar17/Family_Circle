import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../config/theme_config.dart';
import '../../../config/routes.dart';
import '../../../services/family_service.dart';

class ManageNestScreen extends StatefulWidget {
  const ManageNestScreen({super.key});

  @override
  State<ManageNestScreen> createState() => _ManageNestScreenState();
}

class _ManageNestScreenState extends State<ManageNestScreen> {
  final FamilyService _familyService = FamilyService();
  FamilyInfo? _familyInfo;
  bool _isLoading = true;
  bool _locationSharing = true;
  bool _isRegeneratingCode = false;

  @override
  void initState() {
    super.initState();
    _loadFamilyInfo();
  }

  Future<void> _loadFamilyInfo() async {
    try {
      final info = await _familyService.getCurrentFamilyInfo();
      if (mounted) {
        setState(() {
          _familyInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _regenerateCode() async {
    setState(() => _isRegeneratingCode = true);
    try {
      await _familyService.regenerateInviteCode();
      await _loadFamilyInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New invite code generated! Valid for 24 hours.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate code: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegeneratingCode = false);
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return DateFormat('dd MMM, yyyy').format(date);
  }

  String _getExpiryText() {
    if (_familyInfo?.inviteCodeExpiresAt == null) return 'Expired';
    
    final expiresAt = _familyInfo!.inviteCodeExpiresAt!;
    final now = DateTime.now();
    
    if (expiresAt.isBefore(now)) return 'Expired';
    
    final diff = expiresAt.difference(now);
    if (diff.inHours > 0) {
      return 'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    return 'Expires in ${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Nest',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Creation Info
                  Text(
                    'Created by ${_familyInfo?.createdByName ?? 'Unknown'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Created on ${_formatDate(_familyInfo?.createdAt)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),

                  // Nest Code
                  const Text(
                    "Nest's Unique Code",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (_familyInfo?.inviteCode != null) {
                                  Clipboard.setData(ClipboardData(text: _familyInfo!.inviteCode!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Code copied!'),
                                      backgroundColor: AppTheme.successColor,
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                              child: Row(
                                children: [
                                  Text(
                                    _familyInfo?.inviteCode ?? 'N/A',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.copy, color: Colors.white54, size: 18),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  _familyInfo?.isInviteCodeExpired == true
                                      ? Icons.warning_amber_rounded
                                      : Icons.access_time,
                                  size: 14,
                                  color: _familyInfo?.isInviteCodeExpired == true
                                      ? AppTheme.warningColor
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getExpiryText(),
                                  style: TextStyle(
                                    color: _familyInfo?.isInviteCodeExpired == true
                                        ? AppTheme.warningColor
                                        : Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _isRegeneratingCode
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryColor,
                              ),
                            )
                          : TextButton(
                              onPressed: _regenerateCode,
                              child: const Text(
                                'REGENERATE',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),

                  // Circle Name
                  const Text(
                    'Circle name',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _familyInfo?.familyName ?? 'My Family',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showEditNameDialog(),
                        child: const Text(
                          'EDIT',
                          style: TextStyle(
                            color: Color(0xFF4285F4),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),

                  // Circle Admin
                  const Text(
                    'Circle Admin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _familyInfo?.createdByName ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),

                  // Location Sharing
                  const Text(
                    'Location Sharing',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sharing location with this nest',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Switch(
                        value: _locationSharing,
                        onChanged: (val) {
                          setState(() => _locationSharing = val);
                        },
                        activeColor: Colors.white,
                        activeTrackColor: const Color(0xFF4285F4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),

                  // Menu Items
                  _buildMenuItem('Remove Members from nest', null, icon: Icons.chevron_right),
                  const Divider(color: Colors.white24, height: 1),
                  _buildMenuItem('Edit Member Details', null, icon: Icons.chevron_right),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 24),

                  // Destructive Actions
                  _buildMenuItem(
                    'Leave nest',
                    () => _showLeaveConfirmation(),
                    leadingIcon: Icons.exit_to_app,
                    color: AppTheme.errorColor,
                  ),
                  const SizedBox(height: 8),
                  _buildMenuItem(
                    'Delete nest',
                    () => _showDeleteConfirmation(),
                    leadingIcon: Icons.delete_outline,
                    color: AppTheme.errorColor,
                  ),
                ],
              ),
            ),
    );
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _familyInfo?.familyName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Circle Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Circle name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                try {
                  await _familyService.updateFamilyName(controller.text.trim());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name updated!'),
                        backgroundColor: AppTheme.successColor,
                      ),
                    );
                    _loadFamilyInfo();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update name: $e'),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLeaveConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Nest?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to leave this family circle? You will need an invite code to rejoin.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _familyService.leaveFamily();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You have left the family'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.createJoinFamily,
                    (route) => false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to leave: $e'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Nest?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This action cannot be undone. All members will be removed from this family circle.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _familyService.deleteFamily();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Family deleted'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.createJoinFamily,
                    (route) => false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: $e'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(String title, VoidCallback? onTap,
      {IconData? leadingIcon, IconData? icon, Color color = Colors.white}) {
    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, color: color, size: 24),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (icon != null) Icon(icon, color: Colors.blue, size: 24),
          ],
        ),
      ),
    );
  }
}
