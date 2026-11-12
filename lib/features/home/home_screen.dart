import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_tab.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/platform/notifications_bridge.dart';
import '../../shared/widgets/mascot_face.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../app_selection/app_selection_screen.dart';
import '../app_selection/providers/selected_apps_provider.dart';
import '../permissions/permission_setup_screen.dart';
import '../permissions/providers/permission_provider.dart';
import '../settings/providers/preferences_provider.dart';
import '../settings/settings_screen.dart';

/// Screen 3 of docs/SCREEN_SPECIFICATIONS.md, and the app's front door.
///
/// One glance should answer three questions: is the helper listening, what
/// style will my replies be in, and where do I go to write one. Everything
/// that is not one of those three lives behind a tile or the settings icon.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({this.embedded = false, super.key});

  /// True when the shell already owns the chrome (a Scaffold of its own). The
  /// screen then drops its bottom `SafeArea` inset, which would otherwise leave
  /// a dead band above the tab bar.
  final bool embedded;

  /// Sub-screens that are not tabs (permission setup, the app list from a
  /// status pill) are still pushed. The four tabs are not.
  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionEnabled = ref.watch(listenerPermissionProvider);
    final selectedApps = ref.watch(selectedAppsProvider);
    final preferences = ref.watch(preferencesProvider);
    final candidates =
        ref.watch(candidateAppsProvider).value ?? const <CandidateApp>[];
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          bottom: !embedded,
          child: AppSurfaces.centered(
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                AppTheme.spaceSm,
                AppTheme.spaceMd,
                AppTheme.spaceXl,
              ),
              children: [
                Row(
                  children: [
                    Text(
                      strings.appName,
                      style: theme.appBarTheme.titleTextStyle,
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: strings.settings,
                      onPressed: () => _push(context, const SettingsScreen()),
                      icon: const Icon(AppIcons.settingsOutlined, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.white,
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceMd),

                // A compact hero keeps the helper visible without pushing
                // status and the primary action below the fold.
                _HomeHero(
                  permissionEnabled: permissionEnabled,
                  strings: strings,
                ),
                const SizedBox(height: AppTheme.spaceMd),

                // The one thing that actually blocks the feature goes first, in
                // full, and only while it is true. A "granted" banner the user
                // cannot act on is just decoration.
                if (!permissionEnabled) ...[
                  PermissionStatusCard(
                    enabled: permissionEnabled,
                    onManage: () =>
                        _push(context, const PermissionSetupScreen()),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                ],

                // Guarded status in one row of pills: helper state and what it
                // is watching. Tapping any of it goes to the screen that owns it.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceMd - 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _StatusDot(
                              ok: permissionEnabled,
                              label: permissionEnabled ? 'live' : 'off',
                            ),
                            const SizedBox(width: AppTheme.spaceSm),
                            Expanded(
                              child: Text(
                                permissionEnabled
                                    ? strings.listeningTitle
                                    : strings.notListeningTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _push(context, const PermissionSetupScreen()),
                              child: Text(
                                permissionEnabled
                                    ? strings.manage
                                    : strings.enable,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        Wrap(
                          spacing: AppTheme.spaceSm,
                          runSpacing: AppTheme.spaceSm,
                          children: [
                            for (final packageName in selectedApps)
                              AppSurfaces.pill(
                                context,
                                child: Text(
                                  labelForPackage(candidates, packageName),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () =>
                                    _push(context, const AppSelectionScreen()),
                              ),
                            if (selectedApps.isEmpty)
                              AppSurfaces.pill(
                                context,
                                accent: true,
                                onTap: () =>
                                    _push(context, const AppSelectionScreen()),
                                child: Text(
                                  strings.chooseApps,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceMd),

                // The reply style is decided in Settings and applied silently;
                // this row is a mirror, not a question (the panel taught us that
                // asking again is noise).
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceMd - 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              AppIcons.manage,
                              size: 17,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppTheme.spaceSm),
                            Expanded(
                              child: Text(
                                strings.replyStyleTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _push(context, const SettingsScreen()),
                              child: Text(strings.change),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        Wrap(
                          spacing: AppTheme.spaceSm,
                          runSpacing: AppTheme.spaceSm,
                          children: [
                            AppSurfaces.pill(
                              context,
                              accent: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(AppIcons.language, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    preferences.language.label,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppSurfaces.pill(
                              context,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(AppIcons.tone, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    preferences.tone.label,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            AppSurfaces.pill(
                              context,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(AppIcons.length, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    preferences.length.label,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceLg),

                // The one big action. Not a push: the Reply tab already owns
                // the composer, so a second copy never lands on the back stack.
                AppSurfaces.primaryAction(
                  context,
                  label: strings.generateAReply,
                  onPressed: () =>
                      ref.read(appTabProvider.notifier).select(AppTab.reply),
                  icon: const Icon(AppIcons.generate, size: 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.permissionEnabled, required this.strings});

  final bool permissionEnabled;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      color: AppTheme.brand.withValues(alpha: isDark ? 0.13 : 0.065),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.25;
            final mascot = MascotFace(
              size: 72,
              mood: permissionEnabled ? MascotMood.idle : MascotMood.alert,
            );
            final copy = Column(
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  permissionEnabled
                      ? strings.readyTitle
                      : strings.almostThereTitle,
                  textAlign: stacked ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  permissionEnabled
                      ? strings.readySubtitle
                      : strings.almostThereSubtitle,
                  textAlign: stacked ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                children: [
                  mascot,
                  const SizedBox(height: AppTheme.spaceMd - 4),
                  copy,
                ],
              );
            }
            return Row(
              children: [
                mascot,
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(child: copy),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The small state dot: mint when the helper is live, amber when it needs the
/// user. Colour is never the only signal - the label sits right next to it.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colour = ok ? AppTheme.mint : AppTheme.amber;
    // Colour is never the only signal, and TalkBack should hear the word too.
    return Semantics(
      label: label == 'live' ? 'Live' : 'Off',
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: colour.withValues(alpha: 0.35), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
