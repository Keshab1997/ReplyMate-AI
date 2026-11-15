import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_info.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/mascot_face.dart';
import '../../shared/widgets/screen_header.dart';

/// Settings → About. The screen Android users look for and this app did not
/// have: what this is, which version it is, and - because this project's own
/// rule is that capability claims stay honest - what it still does *not*
/// promise.
///
/// It answers three questions a bug report needs: what build, what it is meant
/// to do, and what is known not to be finished. The version is not decorative;
/// `test/app_info_test.dart` holds [AppInfo] to `pubspec.yaml`.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(
            theme.brightness,
            primary: theme.colorScheme.primary,
          ),
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
                // No subtitle: the card below already says the name, and a
                // screen that says it twice reads as two different claims.
                ScreenHeader(title: strings.aboutTitle),
                const SizedBox(height: AppTheme.spaceMd),

                // Identity first: the face the bubble shows, the name, the one
                // honest sentence, and the two facts a report quotes.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const MascotFace(
                              size: 56,
                              glow: false,
                              animate: false,
                              mood: MascotMood.happy,
                            ),
                            const SizedBox(width: AppTheme.spaceMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    AppInfo.name,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    strings.aboutTagline,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        Wrap(
                          spacing: AppTheme.spaceSm,
                          runSpacing: AppTheme.spaceSm,
                          children: <Widget>[
                            _Pill(
                              icon: Icons.tag_rounded,
                              label: strings.versionLine(AppInfo.versionLabel),
                              color: scheme.primary,
                              isDark: isDark,
                            ),
                            _Pill(
                              icon: Icons.science_outlined,
                              label: strings.statusDevelopment,
                              color: AppTheme.amber,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                _Section(
                  title: strings.aboutDoesTitle,
                  icon: Icons.auto_awesome_outlined,
                  body: strings.aboutDoesBody,
                  color: scheme.primary,
                ),
                _Section(
                  title: strings.aboutNeverTitle,
                  icon: Icons.block_outlined,
                  body: strings.aboutNeverBody,
                  color: AppTheme.mint,
                ),
                _Section(
                  title: strings.aboutStatusTitle,
                  icon: Icons.info_outline_rounded,
                  body: strings.aboutStatusBody,
                  color: AppTheme.amber,
                  emphasised: true,
                ),
                _Section(
                  title: strings.aboutLicenseTitle,
                  icon: Icons.gavel_outlined,
                  body: strings.aboutLicenseBody,
                  color: scheme.onSurfaceVariant,
                ),
                _Section(
                  title: strings.aboutCreditsTitle,
                  icon: Icons.text_fields_rounded,
                  body: strings.aboutCreditsBody,
                  color: scheme.onSurfaceVariant,
                ),

                // Selectable, not a link: there is no url_launcher here, and a
                // button that opens nothing would be a lie on a screen whose
                // whole job is telling the truth about itself.
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spaceLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        strings.aboutSourceLabel.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceSm),
                      SelectableText(
                        AppInfo.sourceUrl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12.5,
                          color: scheme.primary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One titled block of prose with an icon. Same shape for every section so the
/// screen reads as a list of answers, not as five bespoke cards.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.body,
    required this.color,
    this.emphasised = false,
  });

  final String title;
  final IconData icon;
  final String body;
  final Color color;

  /// The status block gets a tinted border: it is the one section that says
  /// something is unfinished, and it should not be able to hide.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spaceMd),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: emphasised
                ? color.withValues(alpha: 0.45)
                : scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 17, color: color),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small fact in a rounded chip: version, status.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          // Flexible, so a longer translation wraps inside the pill instead of
          // drawing past the edge of a 320dp screen.
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
