import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';

/// One destination in the Settings hub: a coloured icon, a name, what is inside,
/// and a chevron.
///
/// The icon is not decoration. Ten rows of identical text is what the old
/// screen looked like from a distance; a glyph the eye can find without reading
/// is what makes six rows scannable. The colour comes from the caller so each
/// group keeps a consistent accent (capture is blue, privacy is mint, and so on).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceSm + 4,
          vertical: AppTheme.spaceXs,
        ),
        leading: AppSurfaces.iconBadge(
          context,
          icon: icon,
          color: color,
          size: 40,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
