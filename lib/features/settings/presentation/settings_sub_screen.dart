import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/screen_header.dart';

/// The frame every Settings sub-screen shares: the gradient background, one
/// header with a back arrow, and one column.
///
/// It exists because Settings stopped being one long scroll. Ten sections in a
/// single `ListView` is a list nobody finishes reading: the privacy promises sat
/// below four cards a user had already scrolled past, and "where do I change the
/// tone?" had no answer that started with a tap. Sections are screens now, and
/// every screen is built from this one frame - same padding, same header, same
/// back affordance. A copy of this layout in five files is how a design system
/// rots.
class SettingsSubScreen extends StatelessWidget {
  const SettingsSubScreen({
    required this.title,
    required this.children,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: AppSurfaces.centered(
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                AppTheme.spaceSm,
                AppTheme.spaceMd,
                AppTheme.spaceXl,
              ),
              children: <Widget>[
                ScreenHeader(title: title, subtitle: subtitle),
                const SizedBox(height: AppTheme.spaceMd),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An uppercase group label above a card. The same shape the old single screen
/// used, kept so the sub-screens read as the same product.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.label,
    required this.child,
    this.topSpace = AppTheme.spaceLg,
    super.key,
  });

  final String label;
  final Widget child;
  final double topSpace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topSpace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppTheme.spaceSm),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
