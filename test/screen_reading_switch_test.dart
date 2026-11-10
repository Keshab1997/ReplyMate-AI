import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';
import 'package:replymate/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the outbound calls so the test can prove what the switch did, and
/// answers the permission reads the way Android would.
class _RecordingChannel {
  _RecordingChannel({required this.accessibilityGranted});

  final bool accessibilityGranted;
  final List<String> calls = <String>[];
  final List<bool> screenReadingValues = <bool>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'isScreenReadingAvailable':
        return accessibilityGranted;
      case 'isOverlayEnabled':
        return false;
      case 'isListenerEnabled':
        return true;
      case 'setScreenReadingEnabled':
        screenReadingValues.add((call.arguments as Map)['enabled'] as bool);
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
    required bool accessibilityGranted,
  }) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecordingChannel(
      accessibilityGranted: accessibilityGranted,
    );
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

  SwitchListTile screenReadingSwitch(WidgetTester tester) => tester
      .widgetList<SwitchListTile>(find.byType(SwitchListTile))
      .firstWhere(
        (tile) => (tile.title as Text?)?.data == 'Read the open chat',
      );

  testWidgets('the switch is inert until Android grants accessibility', (
    tester,
  ) async {
    final recorder = await pump(tester, accessibilityGranted: false);

    // Not a crash, not a lie: the switch exists, explains itself, does nothing.
    expect(screenReadingSwitch(tester).value, isFalse);
    expect(screenReadingSwitch(tester).onChanged, isNull);
    expect(find.text('Open accessibility settings'), findsOneWidget);
    expect(recorder.screenReadingValues, isEmpty);

    // The reason is stated, not hidden: on a device that refuses the grant
    // (Android 16+ Advanced Protection) the user is told nothing is read
    // rather than being left with a switch that appears to do nothing.
    expect(find.textContaining('nothing is being read'), findsOneWidget);

    await tester.tap(find.text('Open accessibility settings'));
    await tester.pumpAndSettle();
    expect(recorder.calls, contains('openAccessibilitySettings'));
  });

  testWidgets('turning it on asks first, and a refusal changes nothing', (
    tester,
  ) async {
    final recorder = await pump(tester, accessibilityGranted: true);

    expect(screenReadingSwitch(tester).onChanged, isNotNull);

    await tester.tap(find.text('Read the open chat'));
    await tester.pumpAndSettle();

    // The disclosure is the whole point of this switch: reading the screen is
    // a bigger ask than reading a notification, and consent has to be an
    // answer the user gave - not a side effect of a tap.
    expect(find.text('Before you turn this on'), findsOneWidget);
    expect(recorder.screenReadingValues, isEmpty);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(recorder.screenReadingValues, isEmpty);
    expect(screenReadingSwitch(tester).value, isFalse);
  });

  testWidgets('confirming turns it on and reaches the native layer', (
    tester,
  ) async {
    final recorder = await pump(tester, accessibilityGranted: true);

    await tester.tap(find.text('Read the open chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    // The accessibility service runs with no Flutter engine alive, so the
    // choice has to be persisted natively too.
    expect(recorder.screenReadingValues, <bool>[true]);
    expect(screenReadingSwitch(tester).value, isTrue);
  });

  testWidgets('turning it off again does not ask permission to stop', (
    tester,
  ) async {
    final recorder = await pump(tester, accessibilityGranted: true);

    await tester.tap(find.text('Read the open chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(recorder.screenReadingValues, <bool>[true]);

    await tester.tap(find.text('Read the open chat'));
    await tester.pumpAndSettle();

    // Stopping is never a decision the app argues with.
    expect(find.text('Before you turn this on'), findsNothing);
    expect(recorder.screenReadingValues, <bool>[true, false]);
    expect(screenReadingSwitch(tester).value, isFalse);
  });

  test('a screen reading says where its text came from', () {
    final fromScreen = CapturedNotification.fromMap(<Object?, Object?>{
      'packageName': 'com.whatsapp',
      'key': 'screen:com.whatsapp:123',
      'text': 'ashbe?',
      'fromScreen': true,
    });
    final fromNotification = CapturedNotification.fromMap(<Object?, Object?>{
      'packageName': 'com.whatsapp',
      'key': '0|com.whatsapp|1|null|1000',
      'text': 'ashbe?',
    });

    expect(fromScreen.isScreenRead, isTrue);
    // A notification is the default, so an older native build - one that does
    // not know the flag - is read as a notification rather than as something
    // the user never agreed to.
    expect(fromNotification.isScreenRead, isFalse);
  });
}
