import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/app/app.dart';
import 'package:replymate/app/theme/app_theme.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  /// The Apps tab is mounted from the first frame now, and it asks the native
  /// layer for the installed messaging apps. Without a mock that call never
  /// answers, so the tab's spinner never stops and `pumpAndSettle` waits
  /// forever - the honest no-native-layer answers keep the UI under test.
  const channel = MethodChannel(AppConstants.channelName);

  /// `setupDone` is separate from `onboardingDone` on purpose: since the
  /// first-run setup was added, "onboarded" alone lands on the setup, not on
  /// Home. Tests that want Home have to say both.
  Future<void> boot(
    WidgetTester tester, {
    bool onboardingDone = false,
    bool setupDone = false,
    Map<String, Object> extraPrefs = const {},
  }) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        'isOverlayEnabled' => false,
        'isScreenReadingAvailable' => false,
        _ => null,
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({
      if (onboardingDone) AppConstants.prefOnboardingDone: true,
      if (setupDone) AppConstants.prefSetupDone: true,
      ...extraPrefs,
    });
    await tester.pumpWidget(const ProviderScope(child: ReplyMateApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('first run lands on onboarding with the honest claims', (
    tester,
  ) async {
    await boot(tester);
    expect(find.text('ReplyMate AI'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('never'), findsWidgets);
  });

  testWidgets('completing onboarding lands in the setup, not on Home', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    // The welcome points are read; the choices and the permission come next.
    expect(find.text('Let us set this up together'), findsOneWidget);
    expect(find.text('Notification access not granted'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.prefOnboardingDone), isTrue);
    expect(prefs.getBool(AppConstants.prefSetupDone), isNull);
  });

  testWidgets('finishing the setup reaches Home with a not-granted card', (
    tester,
  ) async {
    await boot(tester, onboardingDone: true);
    await tester.tap(find.text('Start setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open ReplyMate'));
    await tester.pumpAndSettle();

    expect(find.text('Notification access not granted'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.prefSetupDone), isTrue);
  });

  testWidgets('returning users skip onboarding and the setup', (tester) async {
    await boot(tester, onboardingDone: true, setupDone: true);
    expect(find.text('Get started'), findsNothing);
    expect(find.text('Start setup'), findsNothing);
    expect(find.text('Notification access not granted'), findsOneWidget);
  });

  testWidgets('an unfinished setup is offered again on the next launch', (
    tester,
  ) async {
    await boot(tester, onboardingDone: true);
    expect(find.text('Start setup'), findsOneWidget);
    expect(find.text('Notification access not granted'), findsNothing);
  });

  testWidgets('saved appearance is applied to the whole app', (tester) async {
    await boot(
      tester,
      onboardingDone: true,
      setupDone: true,
      extraPrefs: <String, Object>{
        AppConstants.prefThemePalette: 'forest',
        AppConstants.prefThemeMode: 'dark',
      },
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
    expect(app.theme?.colorScheme.primary, AppPalette.forest.primary);
    expect(app.darkTheme?.colorScheme.primary, AppPalette.forest.bright);
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets(
    'composer validates before generating and explains guest-mode configuration',
    (tester) async {
      // A tall test surface: ListView builds lazily, and this test asserts
      // on widgets at the bottom of two different screens.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await boot(tester, onboardingDone: true, setupDone: true);
      await tester.tap(find.text('Generate a reply'));
      await tester.pumpAndSettle();
      expect(find.text('New reply'), findsOneWidget);

      // Empty message: the validation message, not a spinner or a crash.
      await tester.tap(find.text('Generate suggestions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add a message'), findsOneWidget);

      // Real text in guest mode: Firebase/key-pool is unavailable, and the
      // app explains that honestly.
      await tester.enterText(
        find.byType(TextField).first,
        'Can we meet tomorrow?',
      );
      await tester.tap(find.text('Generate suggestions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not configured'), findsOneWidget);
    },
  );

  testWidgets('a fallback notification opens the composer prefilled', (
    tester,
  ) async {
    // The bubble could not be shown, so ReplyMate posted its own notification.
    // Tapping it is a request to answer a message, not to look at Home.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(AppConstants.channelName);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'consumeOverlayContext' => <String, Object?>{
          'source': 'fallback',
          'packageName': 'com.whatsapp',
          'key': 'sbn-1',
          'title': 'Asha',
          'text': 'Can we meet tomorrow?',
          'isTruncated': false,
          'isGrouped': false,
          'isGroupSummary': false,
          'mayBeRedacted': false,
          'hasReplyAction': true,
          'replyActionLabel': 'Reply',
          'postedAtMillis': 1,
        },
        _ => null,
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    SharedPreferences.setMockInitialValues({
      AppConstants.prefOnboardingDone: true,
      AppConstants.prefSetupDone: true,
    });
    await tester.pumpWidget(const ProviderScope(child: ReplyMateApp()));
    await tester.pumpAndSettle();

    expect(find.text('New reply'), findsOneWidget);
    expect(find.text('Can we meet tomorrow?'), findsOneWidget);
  });
}
