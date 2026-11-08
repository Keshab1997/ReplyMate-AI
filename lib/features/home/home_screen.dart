import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/platform/notifications_bridge.dart';
import '../../shared/widgets/mascot_face.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../app_selection/app_selection_screen.dart';
import '../app_selection/providers/selected_apps_provider.dart';
import '../permissions/permission_setup_screen.dart';
import '../permissions/providers/permission_provider.dart';
import '../reply/presentation/reply_composer_screen.dart';
import '../settings/providers/preferences_provider.dart';
import '../settings/settings_screen.dart';

/// Screen 3 of docs/SCREEN_SPECIFICATIONS.md, and the app's front door.
///
/// One glance should answer three questions: is the helper listening, what
/// style will my replies be in, and where do I go to write one. Everything
/// that is not one of those three lives behind a tile or the settings icon.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
          child: ListView(
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
                    icon: const Icon(Icons.settings_outlined, size: 20),
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

              // The helper. It is the app's face, so it gets the middle of the
              // screen at the top - not a 40dp icon in a list row.
              MascotFace(
                size: 96,
                mood: permissionEnabled ? MascotMood.idle : MascotMood.alert,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                permissionEnabled
                    ? strings.readyTitle
                    : strings.almostThereTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppTheme.spaceXs),
              Text(
                permissionEnabled
                    ? strings.readySubtitle
                    : strings.almostThereSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),

              // The one thing that actually blocks the feature goes first, in
              // full, and only while it is true. A "granted" banner the user
              // cannot act on is just decoration.
              if (!permissionEnabled) ...[
                PermissionStatusCard(
                  enabled: permissionEnabled,
                  onManage: () => _push(context, const PermissionSetupScreen()),
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
                            Icons.tune_rounded,
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
                            child: Text(
                              preferences.language.label,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AppSurfaces.pill(
                            context,
                            child: Text(
                              preferences.tone.label,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          AppSurfaces.pill(
                            context,
                            child: Text(
                              preferences.length.label,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),

              // The one big action.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brand.withValues(alpha: 0.45),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: () => _push(context, const ReplyComposerScreen()),
                  icon: const Icon(Icons.auto_awesome, size: 19),
                  label: Text(strings.generateAReply),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),

              const SizedBox(height: AppTheme.spaceLg),
              Text(
                strings.quickStart,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              // Two rows of two, not a GridView with a fixed aspect ratio: at
              // 2x text size a fixed-ratio tile clips its own label, and the
              // user who needs the bigger text is exactly the one who loses it.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Tile(
                        icon: Icons.content_paste_rounded,
                        title: strings.pasteAMessage,
                        subtitle: strings.pasteAMessageSubtitle,
                        onTap: () =>
                            _push(context, const ReplyComposerScreen()),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(
                      child: _Tile(
                        icon: Icons.widgets_outlined,
                        title: strings.supportedApps,
                        subtitle: selectedApps.isEmpty
                            ? strings.noneSelectedYet
                            : strings.selectedAppsCount(selectedApps.length),
                        onTap: () => _push(context, const AppSelectionScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Tile(
                        icon: Icons.bubble_chart_outlined,
                        title: strings.bubbleTitle,
                        subtitle: permissionEnabled
                            ? strings.bubbleShowsOverChats
                            : strings.bubbleNeedsPermission,
                        onTap: () => _push(context, const SettingsScreen()),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(
                      child: _Tile(
                        icon: Icons.vpn_key_outlined,
                        title: strings.connectionTitle,
                        subtitle: strings.guestModeUnlessConfigured,
                        onTap: () => _push(context, const SettingsScreen()),
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

/// A quick-start tile: icon, one line, one supporting line, nothing else.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      container: true,
      // One sentence instead of four fragments: "Paste a message. Reply to the
      // chat you are in."
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Material(
          color: isDark ? Colors.white.withValues(alpha: 0.045) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.tileRadius),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.tileRadius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMd - 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppTheme.brand.withValues(
                        alpha: isDark ? 0.22 : 0.12,
                      ),
                    ),
                    child: Icon(icon, size: 16, color: AppTheme.brandBright),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
