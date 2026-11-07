import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the outbound calls so the test can prove what the switch did, and
/// answers the permission reads the way Android would.
class _RecordingChannel {
  _RecordingChannel({required this.overlayGranted});

  final bool overlayGranted;
  final List<String> calls = <String>[];
  final List<bool> bubbleValues = <bool>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'isOverlayEnabled':
        return overlayGranted;
      case 'isListenerEnabled':
        return true;
      case 'requestNotificationPermission':
        return true;
      case 'setBubbleEnabled':
        bubbleValues.add((call.arguments as Map)['enabled'] as bool);
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

  Future<_RecordingChannel> pump(
    WidgetTester tester, {
    required bool overlayGranted,
  }) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecordingChannel(overlayGranted: overlayGranted);
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

  SwitchListTile bubbleSwitch(WidgetTester tester) => tester
      .widgetList<SwitchListTile>(find.byType(SwitchListTile))
      .firstWhere(
        (tile) => (tile.title as Text?)?.data == 'Floating reply bubble',
      );

  testWidgets('the bubble switch is inert until overlay access is granted', (
    tester,
  ) async {
    final recorder = await pump(tester, overlayGranted: false);

    // Not a crash, not a lie: the switch exists, explains itself, does nothing.
    expect(bubbleSwitch(tester).value, isFalse);
    expect(bubbleSwitch(tester).onChanged, isNull);
    expect(find.textContaining('Display over other apps'), findsOneWidget);
    expect(recorder.bubbleValues, isEmpty);
  });

  testWidgets('with overlay access the switch turns the bubble on natively', (
    tester,
  ) async {
    final recorder = await pump(tester, overlayGranted: true);

    expect(bubbleSwitch(tester).onChanged, isNotNull);

    await tester.tap(find.text('Floating reply bubble'));
    await tester.pumpAndSettle();

    // The switch must reach the native layer, which is what starts the service
    // and what the notification listener reads while no engine is alive.
    expect(recorder.bubbleValues, <bool>[true]);
    expect(bubbleSwitch(tester).value, isTrue);
  });
}
