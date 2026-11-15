import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_info.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../shared/widgets/mascot_face.dart';
import '../../shared/widgets/screen_header.dart';
import '../about/about_screen.dart';
import '../admin/admin_gate_screen.dart';
import '../overlay/providers/bubble_providers.dart';
import 'presentation/ai_screen.dart';
import 'presentation/appearance_screen.dart';
import 'presentation/capture_screen.dart';
import 'presentation/memory_screen.dart';
import 'presentation/privacy_screen.dart';
import 'presentation/reply_defaults_screen.dart';
import 'presentation/settings_tile.dart';
import 'providers/preferences_provider.dart';

/// Settings, as a hub: who this app is, and seven named doors.
///
/// It used to be one screen holding every control the app owns - ten cards in a
/// single scroll, from the language chips down to the privacy promises. That is
/// a list nobody finishes: the tone chips a user wanted were in the third card,
/// the promises they were worried about were in the ninth, and nothing on the
/// screen told them which was which until they scrolled past it.
///
/// Now the same controls live behind six sections plus About. Nothing was
/// removed and no default changed: the screen got shorter, the icons made it
/// scannable, and each group kept the words it already had.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({this.embedded = false, super.key});

  /// See `HomeScreen.embedded`. When true the back button goes too: in a tab
  /// there is nothing above this screen to pop, and `maybePop` would take the
  /// whole app with it.
  final bool embedded;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final preferences = ref.watch(preferencesProvider);
    final bubbleEnabled = ref.watch(bubbleEnabledProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The summary line, not a hint: the point of a hub row is that the answer
    // to "what is in there?" is visible before the tap.
    final replySummary =
        '${preferences.language.label} · ${preferences.tone.label} · '
        '${preferences.length.label} · ${preferences.suggestionCount}';

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
          bottom: !embedded,
          child: AppSurfaces.centered(
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                AppTheme.spaceSm,
                AppTheme.spaceMd,
                AppTheme.spaceXl,
              ),
              children: <Widget>[
                ScreenHeader(
                  title: strings.tabSettings,
                  subtitle: strings.settingsSubtitle,
                  showBack: !embedded,
                ),
                const SizedBox(height: AppTheme.spaceMd),

                // Identity, not a control: the face, the name, and the two
                // facts a bug report needs. It used to be a "Your helper" card
                // in English that repeated the bubble switch's state one card
                // below it - a duplicate *and* an untranslated island.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceMd - 2),
                    child: Row(
                      children: <Widget>[
                        MascotFace(
                          size: 44,
                          glow: false,
                          animate: false,
                          mood: bubbleEnabled
                              ? MascotMood.happy
                              : MascotMood.idle,
                        ),
                        const SizedBox(width: AppTheme.spaceMd - 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                AppInfo.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // A Wrap, not a Row: at a large text scale on a
                              // narrow phone the version and the status must
                              // fall onto two lines instead of overflowing.
                              Wrap(
                                spacing: AppTheme.spaceSm,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  Text(
                                    strings.versionLine(AppInfo.versionLabel),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    strings.statusDevelopment,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.amber,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppTheme.spaceLg),

                // Each row: a coloured icon, a name, and what is behind it.
                // Ordered the way the app is used: what a reply is made of
                // first, then where messages come from, then what it costs,
                // then what it kept, then the promises.
                Column(
                  children: <Widget>[
                    SettingsTile(
                      icon: Icons.tune_rounded,
                      title: strings.replyStyle,
                      subtitle: replySummary,
                      onTap: () => _open(context, const ReplyDefaultsScreen()),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    SettingsTile(
                      icon: Icons.notifications_active_outlined,
                      title: strings.captureSection,
                      subtitle: strings.settingsCaptureHint,
                      color: scheme.secondary,
                      onTap: () => _open(context, const CaptureScreen()),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    SettingsTile(
                      icon: Icons.key_outlined,
                      title: strings.ownKeySection,
                      subtitle: strings.settingsAiHint,
                      color: AppTheme.amber,
                      onTap: () => _open(context, const AiScreen()),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    SettingsTile(
                      icon: Icons.bookmarks_outlined,
                      title: strings.conversationMemorySection,
                      subtitle: strings.settingsMemoryHint,
                      color: AppTheme.mint,
                      onTap: () => _open(context, const MemoryScreen()),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    SettingsTile(
                      icon: Icons.lock_outline_rounded,
                      title: strings.privacySection,
                      subtitle: strings.settingsPrivacyHint,
                      color: AppTheme.mint,
                      onTap: () => _open(context, const PrivacyScreen()),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    SettingsTile(
                      icon: Icons.palette_outlined,
                      title: strings.appearanceTitle,
                      subtitle: strings.appearanceSubtitle,
                      color: scheme.primary,
                      onTap: () => _open(context, const AppearanceScreen()),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: strings.aboutOpenTitle,
                      subtitle: strings.aboutOpenSubtitle,
                      color: scheme.onSurfaceVariant,
                      onTap: () => _open(context, const AboutScreen()),
                    ),
                  ],
                ),

                if (ref.watch(firebaseReadyProvider))
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.spaceLg),
                    child: OutlinedButton.icon(
                      onPressed: () => _open(context, const AdminGateScreen()),
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Admin'),
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
