import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The interface language is a real setting with a real effect, and it is
/// independent of the language replies are written in.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.keshabstudios.replymate/notifications'),
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        'overlayGranted' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.keshabstudios.replymate/notifications'),
      null,
    );
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('english is the default, so nothing moves for existing users', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);
    expect(find.text('Ready when you are'), findsNothing);
    expect(find.text('Almost there'), findsOneWidget);
    expect(find.text('Generate a reply'), findsOneWidget);
  });

  testWidgets('a saved bengali preference renders the bengali home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefAppLanguage: 'bn',
    });
    await pumpHome(tester);
    expect(find.text('আর একটু বাকি'), findsOneWidget);
    expect(find.text('রিপ্লাই বানাও'), findsOneWidget);
    expect(find.text('Generate a reply'), findsNothing);
  });

  testWidgets('switching the language persists and repaints', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);
    expect(find.text('রিপ্লাই বানাও'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    await container
        .read(appLanguageProvider.notifier)
        .setLanguage(AppLanguage.bengali);
    await tester.pumpAndSettle();

    expect(find.text('রিপ্লাই বানাও'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.prefAppLanguage), 'bn');
  });

  testWidgets('a saved hindi preference renders the hindi home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefAppLanguage: 'hi',
    });
    await pumpHome(tester);
    expect(find.text('बस थोड़ा सा बाकी'), findsOneWidget);
    expect(find.text('जवाब बनाएँ'), findsOneWidget);
    expect(find.text('Generate a reply'), findsNothing);
  });

  testWidgets('every interface language is complete, not just the new one', (
    tester,
  ) async {
    // The compiler already refuses a missing getter on a new AppStrings
    // subclass; this catches the other half - a language that exists in the
    // enum but answers with blank or english copy.
    for (final language in AppLanguage.values) {
      final strings = switch (language) {
        AppLanguage.english => const EnglishStrings(),
        AppLanguage.bengali => const BengaliStrings(),
        AppLanguage.hindi => const HindiStrings(),
      };
      expect(strings.language, language);
      for (final value in <String>[
        strings.tabHome,
        strings.tabReply,
        strings.tabApps,
        strings.tabSettings,
        strings.generateAReply,
        strings.almostThereTitle,
        strings.privacySection,
        strings.messagesNeverStored,
        strings.nothingSentAlone,
        strings.screenReadingTitle,
      ]) {
        expect(value.trim(), isNotEmpty, reason: '${language.code} has a gap');
      }
    }
  });
}
