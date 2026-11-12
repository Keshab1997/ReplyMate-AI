import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';

/// The header every inner screen shares: a real [BackButton] in a soft chip,
/// the title, an optional second line, and an optional trailing widget (the
/// mascot, a state pill).
///
/// It exists so the app has **one** back affordance. The chips it replaces
/// were copies of each other, and a copy is how a design system rots.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBack = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        if (showBack)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.065)
                  : Colors.white.withValues(alpha: 0.9),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            child: BackButton(color: theme.colorScheme.primary),
          ),
        if (showBack) const SizedBox(width: AppTheme.spaceMd - 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: 21),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppTheme.spaceMd - 4),
          trailing!,
        ],
      ],
    );
  }
}
