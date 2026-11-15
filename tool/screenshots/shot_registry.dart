// The one file in tool/screenshots/ that belongs to THIS project.
//
// shot_framework.dart and shot_runner_test.dart are the pack's - re-running
// install-agent-pack.sh replaces them, so a fix belongs upstream, not here.
// This file is app code: it names the screens and tells the framework how to
// dress them (real theme, real fonts, the native channel, Hive's temp box).
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replymate/app/theme/app_theme.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shot_framework.dart';

/// The app as a screenshot sees it: its theme, its fonts, its native channel on
/// the day nothing has been granted yet.
final ShotEnv env = ShotEnv(
  // The app's own shell. This import is why the pack leaves the shell to the
  // project: Flutter's material move made `package:flutter/material.dart` and
  // `package:material_ui/material_ui.dart` different ThemeData types, and
  // ReplyMate is on the newer one.
  app: (shot, home) => MaterialApp(
    theme: shot.dark ? AppTheme.dark() : AppTheme.light(),
    // The corner ribbon is a debug artefact, not part of the screen.
    debugShowCheckedModeBanner: false,
    home: home,
  ),
  wrap: (child) => ProviderScope(child: child),
  fontAssets: const <String, String>{
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'NotoSansBengali': 'assets/fonts/NotoSansBengali-Variable.ttf',
    'NotoSansDevanagari': 'assets/fonts/NotoSansDevanagari-Variable.ttf',
  },
  bridgeChannel: AppConstants.channelName,
  // The honest "fresh install, nothing granted" answers - the same ones the
  // widget tests use. A shot should show the empty state, not a red screen.
  bridgeAnswers: const <String, Object?>{
    'candidateApps': <Object?>[],
    'installedApps': <Object?>[],
    'isListenerEnabled': false,
    'overlayGranted': false,
    'consumeLaunchContext': null,
    'screenReadingStatus': <Object?, Object?>{},
    'bubbleStatus': <Object?, Object?>{},
  },
  // Conversation memory opens a Hive box as soon as its card is built; without
  // one the memory screen photographs a red error instead of a settings page.
  // The pack stays free of plugin imports so it can drop into any project, so
  // seeding lives here: this app really does use shared_preferences.
  seedPreferences: (values) async {
    // The mock initialiser is @visibleForTesting and the analyzer only looks at
    // the directory name, so tool/ has to say it means it.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(values);
  },
  setUpAll: () async {
    Hive.init(Directory.systemTemp.createTempSync('replymate-shots').path);
  },
);

/// The screens worth looking at, and the awkward cases with them.
///
/// Short on purpose: a screenshot tool that renders everything becomes a
/// maintenance job of its own.
final List<Shot> shots = <Shot>[
  Shot(name: 'settings-hub', build: () => const SettingsScreen()),
  Shot(name: 'settings-reply', build: () => const ReplyDefaultsScreen()),
  Shot(
    name: 'settings-reply-bn',
    build: () => const ReplyDefaultsScreen(),
    preferences: <String, Object>{
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
    preferences: <String, Object>{AppConstants.prefAppLanguage: 'bn'},
  ),
  Shot(name: 'home', build: () => const HomeScreen(embedded: true)),
  Shot(
    name: 'reply-composer',
    build: () => const ReplyComposerScreen(embedded: true),
  ),
  Shot(name: 'create-message', build: () => const CreateMessageScreen()),

  // The cases that catch what a comfortable phone hides.
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
