import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';

/// The permission banner shown on Home and the permission screen: one card,
/// three honest states (checking / granted / not granted). Never claims
/// access it has not verified (FR-02, FR-10).
class PermissionStatusCard extends StatelessWidget {
  const PermissionStatusCard({
    required this.enabled,
    required this.strings,
    this.checking = false,
    this.onManage,
    super.key,
  });

  final bool enabled;

  /// Localization lives in the caller, like every other screen: the card used
  /// to hardcode its three states in English, so a Bengali or Hindi session
  /// still showed the amber banner in English - the one thing on Home the
  /// setup-path sweep missed.
  final AppStrings strings;
  final bool checking;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color tint;
    final Color foreground;
    final IconData icon;
    final String title;
    final String subtitle;
    if (checking) {
      tint = scheme.surfaceContainerHighest.withValues(alpha: 0.65);
      foreground = scheme.onSurfaceVariant;
      icon = Icons.hourglass_top_rounded;
      title = strings.checkingNotificationAccess;
      subtitle = strings.checkingNotificationAccessBody;
    } else if (enabled) {
      tint = AppTheme.mint.withValues(alpha: isDark ? 0.10 : 0.08);
      foreground = isDark ? AppTheme.mint : const Color(0xFF087F5B);
      icon = Icons.check_circle_rounded;
      title = strings.permissionGrantedTitle;
      subtitle = strings.permissionGrantedBody;
    } else {
      tint = AppTheme.amber.withValues(alpha: isDark ? 0.10 : 0.09);
      foreground = isDark ? AppTheme.amber : const Color(0xFF9A5B00);
      icon = Icons.notifications_off_outlined;
      title = strings.permissionMissingTitle;
      subtitle = strings.permissionMissingBody;
    }
    return Card(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSurfaces.iconBadge(context, icon: icon, color: foreground),
                const SizedBox(width: AppTheme.spaceMd - 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceXs),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onManage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spaceSm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.tune_rounded, size: 17),
                    label: Text(strings.manage),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
