import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// The permission banner shown on Home and the permission screen: one card,
/// three honest states (checking / granted / not granted). Never claims
/// access it has not verified (FR-02, FR-10).
class PermissionStatusCard extends StatelessWidget {
  const PermissionStatusCard({
    required this.enabled,
    this.checking = false,
    this.onManage,
    super.key,
  });

  final bool enabled;
  final bool checking;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color tint;
    final IconData icon;
    final String title;
    final String subtitle;
    if (checking) {
      tint = scheme.surfaceContainerHighest;
      icon = Icons.hourglass_top_rounded;
      title = 'Checking notification access';
      subtitle = 'Reading the current state from Android.';
    } else if (enabled) {
      tint = scheme.primaryContainer.withValues(alpha: 0.35);
      icon = Icons.check_circle_rounded;
      title = 'Notification access enabled';
      subtitle = 'ReplyMate sees notifications from your selected apps only.';
    } else {
      tint = scheme.errorContainer.withValues(alpha: 0.35);
      icon = Icons.error_outline_rounded;
      title = 'Notification access not granted';
      subtitle =
          'Without it, paste or select text manually - replies still work.';
    }
    return Card(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppTheme.spaceMd - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (onManage != null)
              TextButton(onPressed: onManage, child: const Text('Manage')),
          ],
        ),
      ),
    );
  }
}
