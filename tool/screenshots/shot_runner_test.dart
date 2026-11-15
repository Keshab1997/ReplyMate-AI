// Renders screens to PNGs so a human (or an agent with eyes) can look at them
// without a device and without spending a CI run.
//
//     python3 tool/screenshots.py --list
//     python3 tool/screenshots.py --shot settings-reply
//     python3 tool/screenshots.py                      # every shot
//
// Two flags keep this out of everybody else's way:
//
//   * it lives in tool/, not test/, so a plain `flutter test` never discovers
//     it - CI stays as fast as it was and cannot go red because a golden moved;
//   * it is a no-op unless `--dart-define=SHOTS=1` is passed, so even a direct
//     run of this file cannot start writing PNGs by accident.
//
// Images land in .agent-screens/local/ (git-ignored). They are throwaway
// evidence, never fixtures: nothing may read them back as a test input.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replymate/app/theme/app_theme.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shot_registry.dart';

/// The gate. No define, no rendering.
///
/// Read as a string, not `bool.fromEnvironment`: that only understands the
/// literals "true"/"false", so `--dart-define=SHOTS=1` - the spelling in the
/// docs and in tool/screenshots.py - would have left the tool silently off.
const String _shotsFlag = String.fromEnvironment('SHOTS');
const bool shotsEnabled = _shotsFlag == '1' || _shotsFlag == 'true';

/// Which shots, by name. Empty means all of them.
const String requestedShots = String.fromEnvironment('SHOT');

/// Where the PNGs go. Two spellings of one directory on purpose: Flutter
/// resolves a golden path against *this file's* directory, while dart:io
/// creates directories against the *package root*. Using one constant for both
/// wrote the images to /home/.agent-screens and failed on permissions.
const String _goldenDir = '../../.agent-screens/local';
const String _outputDir = '.agent-screens/local';

const MethodChannel _channel = MethodChannel(AppConstants.channelName);

/// The app's own font files, loaded by family name so the picture is set in the
/// fonts a phone would use. Without this every glyph is a solid box and the
/// screenshot is worse than useless - it looks like a layout bug.
Future<void> _loadAppFonts() async {
  const families = <String, String>{
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'NotoSansBengali': 'assets/fonts/NotoSansBengali-Variable.ttf',
    'NotoSansDevanagari': 'assets/fonts/NotoSansDevanagari-Variable.ttf',
  };
  for (final entry in families.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  // Icons are a font too, and it ships with the SDK rather than the repo.
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '/var/tmp/flutter';
  final icons = File(
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!icons.existsSync()) {
    throw StateError(
      'MaterialIcons font not found at ${icons.path}. Icons would render as '
      'boxes, so this stops instead of writing a misleading screenshot. Set '
      'FLUTTER_ROOT if the SDK lives somewhere else.',
    );
  }
  final bytes = icons.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Every screen here talks to the native layer through one channel. A shot gets
/// the honest "nothing is granted yet" answers rather than a red screen.
void _mockBridge(TestWidgetsFlutterBinding binding) {
  binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    return switch (call.method) {
      'candidateApps' => <Object?>[],
      'installedApps' => <Object?>[],
      'isListenerEnabled' => false,
      'overlayGranted' => false,
      'consumeLaunchContext' => null,
      'screenReadingStatus' => <Object?, Object?>{},
      'bubbleStatus' => <Object?, Object?>{},
      _ => null,
    };
  });
}

void main() {
  if (!shotsEnabled) {
    test('screenshot runner is off (pass --dart-define=SHOTS=1)', () {});
    return;
  }

  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final selected = selectShots(requestedShots);

  setUpAll(() async {
    await _loadAppFonts();
    _mockBridge(binding);
    // Conversation memory opens a Hive box as soon as its card is built. With
    // no Hive the memory screen renders a red error instead of a settings page
    // - so the shot needs a scratch box, in a temp dir that is never the app's.
    Hive.init(Directory.systemTemp.createTempSync('replymate-shots').path);
    Directory(_outputDir).createSync(recursive: true);
  });

  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  if (selected.isEmpty) {
    test('no shot matched --dart-define=SHOT=$requestedShots', () {
      fail(
        'Nothing matched. Known shots: '
        '${shots.map((shot) => shot.name).join(', ')}',
      );
    });
    return;
  }

  for (final shot in selected) {
    testWidgets('shot: ${shot.name} (${shot.sizeLabel})', (tester) async {
      // The seeding API is @visibleForTesting, and this file is a test even
      // though it lives in tool/ - the analyzer only checks the directory name.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(shot.prefs);
      tester.view.physicalSize = Size(
        shot.logicalSize.width * shot.dpr,
        shot.logicalSize.height * shot.dpr,
      );
      tester.view.devicePixelRatio = shot.dpr;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            // The app's own theme, not a bare Material one: a screenshot taken
            // in the wrong skin is a screenshot of a different app.
            theme: shot.dark ? AppTheme.dark() : AppTheme.light(),
            // The corner ribbon is a debug artefact, not part of the screen.
            debugShowCheckedModeBanner: false,
            home: MediaQuery(
              data: MediaQueryData(
                size: shot.logicalSize,
                textScaler: TextScaler.linear(shot.textScale),
              ),
              child: shot.build(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Asset images (the mascot) decode on a real event loop, which the fake
      // async of a widget test never advances. Without this the mascot is a
      // coloured circle in every screenshot - a picture that lies about the app.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();

      // A layout exception is the most valuable thing a screenshot can tell
      // you, and it is invisible in the pixels. Fail loudly, with the name.
      final exception = tester.takeException();
      expect(exception, isNull, reason: '${shot.name} threw while rendering');

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$_goldenDir/${shot.name}.png'),
      );
    });
  }
}
