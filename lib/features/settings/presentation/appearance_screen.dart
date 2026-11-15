import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_theme_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import 'settings_sub_screen.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final appearance = ref.watch(appThemePreferencesProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(appThemePreferencesProvider.notifier);

    return SettingsSubScreen(
      title: strings.appearanceTitle,
      subtitle: strings.appearanceSubtitle,
      children: [
        SettingsSection(
          label: strings.appearanceMode,
          topSpace: AppTheme.spaceSm,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceSm),
              child: SegmentedButton<AppAppearanceMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppAppearanceMode.system,
                    label: Text(strings.appearanceSystem),
                    icon: const Icon(Icons.settings_suggest_outlined),
                  ),
                  ButtonSegment(
                    value: AppAppearanceMode.light,
                    label: Text(strings.appearanceLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppAppearanceMode.dark,
                    label: Text(strings.appearanceDark),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {appearance.mode},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) notifier.setMode(selected.first);
                },
              ),
            ),
          ),
        ),
        SettingsSection(
          label: strings.appearanceColors,
          child: Column(
            children: [
              for (final palette in AppPalette.values) ...[
                _PaletteTile(
                  palette: palette,
                  title: _paletteTitle(strings, palette),
                  selected: palette == appearance.palette,
                  onTap: () => notifier.setPalette(palette),
                ),
                if (palette != AppPalette.values.last)
                  const SizedBox(height: AppTheme.spaceSm),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  '${_paletteTitle(strings, appearance.palette)} · '
                  '${_modeTitle(strings, appearance.mode)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _paletteTitle(AppStrings strings, AppPalette palette) =>
      switch (palette) {
        AppPalette.violet => strings.paletteViolet,
        AppPalette.forest => strings.paletteForest,
        AppPalette.rose => strings.paletteRose,
        AppPalette.amber => strings.paletteAmber,
        AppPalette.ocean => strings.paletteOcean,
      };

  static String _modeTitle(AppStrings strings, AppAppearanceMode mode) =>
      switch (mode) {
        AppAppearanceMode.system => strings.appearanceSystem,
        AppAppearanceMode.light => strings.appearanceLight,
        AppAppearanceMode.dark => strings.appearanceDark,
      };
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = palette.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.25),
                        width: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: scheme.primary, size: 21)
                  else
                    Icon(
                      Icons.circle_outlined,
                      color: scheme.outlineVariant,
                      size: 21,
                    ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceSm + 2),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: theme.brightness == Brightness.dark
                      ? Color.alphaBlend(
                          accent.withValues(alpha: 0.14),
                          const Color(0xFF17151E),
                        )
                      : Color.alphaBlend(
                          accent.withValues(alpha: 0.055),
                          const Color(0xFFFFFEFC),
                        ),
                  border: Border.all(color: accent.withValues(alpha: 0.23)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 17, color: accent),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(
                      child: Text(
                        'ReplyMate',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      width: 54,
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: [accent, palette.secondary],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
