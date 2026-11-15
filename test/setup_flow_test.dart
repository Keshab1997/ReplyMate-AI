import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/app/app.dart';
import 'package:replymate/app/app_shell.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/onboarding/onboarding_screen.dart';
import 'package:replymate/features/settings/providers/preferences_provider.dart';
import 'package:replymate/features/setup/setup_flow_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The first-run setup: the door the launch goes through, the four steps, and
/// the two promises the flow makes - "your choices are saved as you make them"
/// and "leaving does not pretend you finished".
const MethodChannel bridgeChannel = MethodChannel(AppConstants.channelName);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        'isOverlayEnabled' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      null,
    );
  });

  Widget app(Widget home, {AppLanguage? language}) {
    return ProviderScope(
      overrides: [
        if (language != null)
          appLanguageProvider.overrideWith(() => _FixedLanguage(language)),
      ],
      child: MaterialApp(home: home),
    );
  }

  /// `pumpAndSettle` is not usable here: the mascot breathes for ever, so a
  /// settle would wait until the test timed out. Three pumps is enough for the
  /// FutureBuilder, the pref read and one page transition.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the launch decides between three doors', () {
    testWidgets('a brand-new install reads the welcome first', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(app(const StartupGate()));
      await settle(tester);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(SetupFlowScreen), findsNothing);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('welcome read, setup unfinished: the setup appears', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefOnboardingDone: true,
      });
      await tester.pumpWidget(app(const StartupGate()));
      await settle(tester);

      expect(find.byType(SetupFlowScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('a finished setup goes straight into the app', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefOnboardingDone: true,
        AppConstants.prefSetupDone: true,
      });
      await tester.pumpWidget(app(const StartupGate()));
      await settle(tester);

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(SetupFlowScreen), findsNothing);
    });
  });

  group('the flow itself', () {
    testWidgets('four steps, in order, and the last one opens the app', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefOnboardingDone: true,
      });
      final strings = const EnglishStrings();
      await tester.pumpWidget(app(const SetupFlowScreen()));
      await settle(tester);

      // Step 1 is a welcome, not a wall: it says what is coming.
      expect(find.text(strings.setupWelcomeTitle), findsOneWidget);
      expect(find.text(strings.setupWelcomePointApps), findsOneWidget);
      expect(find.text(strings.setupStepCount(1, 4)), findsOneWidget);

      await tester.tap(find.text(strings.setupStart));
      await settle(tester);
      expect(find.text(strings.setupStyleTitle), findsOneWidget);
      expect(find.text(strings.setupStepCount(2, 4)), findsOneWidget);

      await tester.tap(find.text(strings.setupNext));
      await settle(tester);
      expect(find.text(strings.setupCaptureTitle), findsOneWidget);

      await tester.tap(find.text(strings.setupNext));
      await settle(tester);
      expect(find.text(strings.setupReadyTitle), findsOneWidget);
      expect(find.text(strings.setupStepCount(4, 4)), findsOneWidget);

      await tester.tap(find.text(strings.setupFinish));
      await settle(tester);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.prefSetupDone), isTrue);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('"Later" enters the app without claiming the setup is done', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefOnboardingDone: true,
      });
      final strings = const EnglishStrings();
      await tester.pumpWidget(app(const SetupFlowScreen()));
      await settle(tester);

      await tester.tap(find.text(strings.setupLater));
      await settle(tester);

      final prefs = await SharedPreferences.getInstance();
      // Not set: the next launch offers the setup again, which is the honest
      // reading of "I did not do it".
      expect(prefs.getBool(AppConstants.prefSetupDone), isNull);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('a choice is saved the moment it is made', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: const SetupFlowScreen(startAt: SetupStep.style),
          ),
        ),
      );
      await settle(tester);

      // The interface language, then the reply tone. Both are settings the
      // rest of the app reads, so a lost tap here is a visible bug later.
      await tester.tap(find.text(AppLanguage.bengali.label).first);
      await settle(tester);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppConstants.prefAppLanguage),
        AppLanguage.bengali.code,
      );

      // The tone chips sit below the fold on a 390x844 phone; the scroll is part
      // of what the test checks, because a chip a user cannot reach is not a
      // setting.
      final funny = find.text(ReplyTone.funny.label).first;
      await tester.dragUntilVisible(
        funny,
        find.byType(SingleChildScrollView).first,
        const Offset(0, -140),
      );
      await tester.tap(funny);
      await settle(tester);
      expect(container.read(preferencesProvider).tone, ReplyTone.funny);
      expect(
        prefs.getString(AppConstants.prefDefaultTone),
        ReplyTone.funny.name,
      );
    });

    testWidgets('the summary tells the truth about a refused permission', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final strings = const EnglishStrings();
      await tester.pumpWidget(
        app(const SetupFlowScreen(startAt: SetupStep.ready)),
      );
      await settle(tester);

      // Nothing was granted in this test, so the summary must not show a tick.
      expect(find.text(strings.setupNotifications(0)), findsOneWidget);
      expect(find.text(strings.setupNotifications(1)), findsNothing);
      expect(find.text(strings.setupAppsNone), findsOneWidget);
    });

    testWidgets('the flow speaks Bengali when that is the app language', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final strings = const BengaliStrings();
      await tester.pumpWidget(
        app(const SetupFlowScreen(), language: AppLanguage.bengali),
      );
      await settle(tester);

      expect(find.text(strings.setupWelcomeTitle), findsOneWidget);
      expect(find.text(strings.setupStart), findsOneWidget);
      expect(find.text(const EnglishStrings().setupWelcomeTitle), findsNothing);
    });
  });

  testWidgets('the welcome hands over to the setup, not to a bare home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(const OnboardingScreen()));
    await settle(tester);

    await tester.tap(find.text(const EnglishStrings().onboardingGetStarted));
    await settle(tester);

    expect(find.byType(SetupFlowScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.prefOnboardingDone), isTrue);
    expect(prefs.getBool(AppConstants.prefSetupDone), isNull);
  });
}

/// A language that is already chosen, so the first frame is translated without
/// waiting on the pref read.
class _FixedLanguage extends AppLanguageNotifier {
  _FixedLanguage(this.value);

  final AppLanguage value;

  @override
  AppLanguage build() => value;
}
