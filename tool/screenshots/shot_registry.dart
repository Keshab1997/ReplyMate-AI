import 'package:material_ui/material_ui.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/about/about_screen.dart';
import 'package:replymate/features/home/home_screen.dart';
import 'package:replymate/features/reply/presentation/create_message_screen.dart';
import 'package:replymate/features/reply/presentation/reply_composer_screen.dart';
import 'package:replymate/features/settings/presentation/ai_screen.dart';
import 'package:replymate/features/settings/presentation/capture_screen.dart';
import 'package:replymate/features/settings/presentation/memory_screen.dart';
import 'package:replymate/features/settings/presentation/privacy_screen.dart';
import 'package:replymate/features/settings/presentation/reply_defaults_screen.dart';
import 'package:replymate/features/settings/settings_screen.dart';

/// One screen, rendered the way a phone would render it.
///
/// `name` is what you pass to `tool/screenshots.py --shot <name>`, and it is
/// also the file name of the PNG. Keep it kebab-case and stable: it is the only
/// handle the tool has on a screen.
class Shot {
  const Shot({
    required this.name,
    required this.build,
    this.prefs = const <String, Object>{},
    this.logicalSize = const Size(390, 844),
    this.dpr = 2,
    this.dark = true,
    this.textScale = 1,
  });

  final String name;
  final Widget Function() build;

  /// SharedPreferences values seeded before the pump. This is how a shot can
  /// show a Bengali session, a professional tone, or a count of three without
  /// anybody tapping anything.
  final Map<String, Object> prefs;

  /// Logical size. 390x844 is a modern phone; 320x568 and 360x640 are in the
  /// registry as explicit narrow cases because that is where layouts break.
  final Size logicalSize;
  final double dpr;
  final bool dark;
  final double textScale;

  String get sizeLabel =>
      '${logicalSize.width.toInt()}x'
      '${logicalSize.height.toInt()}@${dpr}x';
}

/// The screens worth looking at, and why each one is here.
///
/// This list is deliberately short. A screenshot tool that renders everything
/// becomes a maintenance job of its own; these are the surfaces where a change
/// is easy to describe and hard to picture - the Settings hub and its
/// sub-screens (new structure), the composer (a conversation), the home screen
/// (the first thing anybody sees).
final List<Shot> shots = <Shot>[
  Shot(name: 'settings-hub', build: () => const SettingsScreen()),
  Shot(name: 'settings-reply', build: () => const ReplyDefaultsScreen()),
  Shot(
    name: 'settings-reply-bn',
    build: () => const ReplyDefaultsScreen(),
    prefs: <String, Object>{
      AppConstants.prefAppLanguage: 'bn',
      AppConstants.prefDefaultTone: 'professional',
      AppConstants.prefSuggestionCount: 3,
    },
  ),
  Shot(name: 'settings-capture', build: () => const CaptureScreen()),
  Shot(name: 'settings-ai', build: () => const AiScreen()),
  Shot(name: 'settings-memory', build: () => const MemoryScreen()),
  Shot(name: 'settings-privacy', build: () => const PrivacyScreen()),
  Shot(name: 'about', build: () => const AboutScreen()),
  Shot(
    name: 'about-bn',
    build: () => const AboutScreen(),
    prefs: <String, Object>{AppConstants.prefAppLanguage: 'bn'},
  ),
  Shot(name: 'home', build: () => const HomeScreen(embedded: true)),
  Shot(
    name: 'reply-composer',
    build: () => const ReplyComposerScreen(embedded: true),
  ),
  Shot(name: 'create-message', build: () => const CreateMessageScreen()),

  // The two cases that catch what a comfortable phone hides.
  Shot(
    name: 'settings-hub-narrow',
    build: () => const SettingsScreen(),
    logicalSize: const Size(320, 1400),
  ),
  Shot(
    name: 'settings-reply-bigtext',
    build: () => const ReplyDefaultsScreen(),
    textScale: 1.6,
  ),
  Shot(
    name: 'settings-hub-light',
    build: () => const SettingsScreen(),
    dark: false,
  ),
];

/// `--dart-define=SHOT=a,b` selects; no value means every shot, which is the
/// right default for a tool a human runs on purpose.
List<Shot> selectShots(String requested) {
  final wanted = requested
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
  if (wanted.isEmpty) return shots;
  return shots.where((shot) => wanted.contains(shot.name)).toList();
}
