import 'package:flutter/material.dart';

import '../../../config/theme_config.dart';
import '../../../services/family_service.dart';

/// The member sheet shown over the home map when a member is opened.
class MemberFocusCard extends StatelessWidget {
  const MemberFocusCard({
    super.key,
    required this.member,
    required this.onClose,
    required this.onCall,
    required this.onMessage,
    required this.onHistory,
    required this.onToggleRoute,
    required this.onNavigate,
    this.showingRoute = false,
    this.loadingRoute = false,
    this.routeSummary,
  });

  final FamilyMemberData member;
  final VoidCallback onClose;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onHistory;
  final VoidCallback onToggleRoute;
  final VoidCallback onNavigate;
  final bool showingRoute;
  final bool loadingRoute;
  final String? routeSummary;

  @override
  Widget build(BuildContext context) {
    final name = member.displayName;
    final batteryColor = member.battery < 20
        ? AppTheme.errorColor
        : member.battery < 50
            ? AppTheme.warningColor
            : AppTheme.successColor;

    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
                  backgroundImage:
                      member.photoUrl != null ? NetworkImage(member.photoUrl!) : null,
                  child: member.photoUrl == null
                      ? Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: member.isOnline
                                  ? AppTheme.successColor
                                  : AppTheme.textHint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              member.statusText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Chip(
                            icon: Icons.battery_std_rounded,
                            label: '${member.battery}%',
                            color: batteryColor,
                          ),
                          _Chip(
                            icon: Icons.schedule_rounded,
                            label: member.lastSeenText,
                            color: AppTheme.textSecondary,
                          ),
                          if (member.isMoving && member.speedKmh >= 1)
                            _Chip(
                              icon: Icons.speed_rounded,
                              label: '${member.speedKmh.round()} km/h',
                              color: AppTheme.warningColor,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (showingRoute && routeSummary != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.route_rounded, size: 16, color: AppTheme.primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      routeSummary!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  _ActionButton(icon: Icons.phone_rounded, tooltip: 'Call', onPressed: onCall),
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.message_rounded, tooltip: 'Message', onPressed: onMessage),
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.history_rounded, tooltip: 'History', onPressed: onHistory),
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: showingRoute ? Icons.close_rounded : Icons.alt_route_rounded,
                    tooltip: showingRoute ? 'Hide route' : 'Preview route',
                    onPressed: loadingRoute ? null : onToggleRoute,
                    busy: loadingRoute,
                    highlighted: showingRoute,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: onNavigate,
                        icon: const Icon(Icons.directions_rounded, size: 20),
                        label: const Text('Navigate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: AppTheme.primaryColor,
            backgroundColor:
                highlighted ? AppTheme.primaryColor.withOpacity(0.1) : null,
            side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.35)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 22),
        ),
      ),
    );
  }
}
