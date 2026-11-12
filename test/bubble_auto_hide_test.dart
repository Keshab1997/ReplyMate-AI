import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/overlay/providers/bubble_providers.dart';
import 'package:replymate/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the outbound calls so the test can prove that a hide-after choice
/// reaches the native layer - the service reads it with no engine alive.
class _RecordingChannel {
  final List<Map<Object?, Object?>> autoHideCalls = <Map<Object?, Object?>>[];

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'isOverlayEnabled':
        return true;
      case 'isListenerEnabled':
        return true;
      case 'setBubbleAutoHideMinutes':
        autoHideCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
      default:
        return null;
    }
  }
}

const MethodChannel _channel = MethodChannel(AppConstants.channelName);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  Future<_RecordingChannel> pumpSettings(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
    final recorder = _RecordingChannel();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      recorder.handle,
    );
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    return recorder;
  }

  test('an unknown stored value falls back to ten minutes, never to "never"', () {
    // A hand-edited preference, an old build, or a future value must not turn a
    // ten-minute bubble into one that sits there forever.
    expect(BubbleAutoHideNotifier.normalise(999), 10);
    expect(BubbleAutoHideNotifier.normalise(null), 10);
    expect(BubbleAutoHideNotifier.normalise(-5), 10);
    // The documented choices survive untouched, including the honest zero.
    expect(BubbleAutoHideNotifier.normalise(5), 5);
    expect(BubbleAutoHideNotifier.normalise(30), 30);
    expect(BubbleAutoHideNotifier.normalise(0), 0);
  });

  testWidgets('the hide-after row is hidden while the bubble is off', (
    tester,
  ) async {
    await pumpSettings(tester);

    // A timer for a bubble that does not exist would be a setting that cannot
    // do anything.
    expect(find.text('Hide the bubble after'), findsNothing);
  });

  testWidgets(
    'with the bubble on, the default is ten minutes and it reads out',
    (tester) async {
      await pumpSettings(
        tester,
        prefs: <String, Object>{AppConstants.prefBubbleEnabled: true},
      );

      expect(find.text('Hide the bubble after'), findsOneWidget);
      expect(find.text('10 min'), findsWidgets);
    },
  );

  testWidgets('choosing "Never" reaches the native layer as 0', (tester) async {
    final recorder = await pumpSettings(
      tester,
      prefs: <String, Object>{AppConstants.prefBubbleEnabled: true},
    );

    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();

    // The service has no engine to ask, so the choice must be mirrored natively.
    expect(recorder.autoHideCalls, <Map<Object?, Object?>>[
      <Object?, Object?>{'minutes': 0},
    ]);
    expect(find.text('Never'), findsWidgets);
  });

  testWidgets('a stored choice is loaded and shown', (tester) async {
    await pumpSettings(
      tester,
      prefs: <String, Object>{
        AppConstants.prefBubbleEnabled: true,
        AppConstants.prefBubbleAutoHideMinutes: 30,
      },
    );

    expect(find.text('30 min'), findsWidgets);
  });
}
