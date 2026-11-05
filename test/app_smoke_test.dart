import 'package:flutter/material.dart';
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
    'composer validates before generating and explains the missing backend',
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

      // Real text: batch 1 has no AI backend yet, and says so honestly.
      await tester.enterText(
        find.byType(TextField).first,
        'Can we meet tomorrow?',
      );
      await tester.tap(find.text('Generate suggestions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not configured'), findsOneWidget);
    },
  );
}
