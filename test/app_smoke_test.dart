import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/app/app.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(WidgetTester tester, {bool onboardingDone = false}) async {
    SharedPreferences.setMockInitialValues({
      if (onboardingDone) AppConstants.prefOnboardingDone: true,
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

  testWidgets('completing onboarding reaches Home with a not-granted card', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Notification access not granted'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.prefOnboardingDone), isTrue);
  });

  testWidgets('returning users skip onboarding', (tester) async {
    await boot(tester, onboardingDone: true);
    expect(find.text('Get started'), findsNothing);
    expect(find.text('Notification access not granted'), findsOneWidget);
  });

  testWidgets(
    'composer validates before generating and explains guest-mode configuration',
    (tester) async {
      // A tall test surface: ListView builds lazily, and this test asserts
      // on widgets at the bottom of two different screens.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await boot(tester, onboardingDone: true);
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
    });
    await tester.pumpWidget(const ProviderScope(child: ReplyMateApp()));
    await tester.pumpAndSettle();

    expect(find.text('New reply'), findsOneWidget);
    expect(find.text('Can we meet tomorrow?'), findsOneWidget);
  });
}
