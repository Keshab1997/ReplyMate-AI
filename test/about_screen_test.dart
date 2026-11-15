import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/constants/app_info.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/about/about_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The About screen is the one place in the app that states what this build is
/// and what it is not. Both halves are load-bearing: a version nobody can read
/// makes a bug report useless, and a status line that is missing makes the app
/// claim more than it can do.
Future<void> pumpAbout(WidgetTester tester, {String? language}) async {
  SharedPreferences.setMockInitialValues({
    AppConstants.prefAppLanguage: ?language,
  });
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: AboutScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the build states its own version', (tester) async {
    await pumpAbout(tester);

    expect(find.text(AppInfo.name), findsOneWidget);
    expect(find.text('Version ${AppInfo.versionLabel}'), findsOneWidget);
    // The number must be a version a maintainer can act on, not a label.
    expect(AppInfo.versionLabel, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
  });

  testWidgets('the status line admits it is a development build', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.text(const EnglishStrings().statusDevelopment), findsOneWidget);
    expect(find.text(const EnglishStrings().aboutStatusTitle), findsOneWidget);
    // The honest half: unfinished pieces are named, not smoothed over.
    final status = const EnglishStrings().aboutStatusBody;
    expect(status, contains('not verified'));
    expect(status, contains('not release-ready'));
  });

  testWidgets('it says what the app never does, not only what it does', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.text(const EnglishStrings().aboutDoesTitle), findsOneWidget);
    expect(find.text(const EnglishStrings().aboutNeverTitle), findsOneWidget);
    expect(
      const EnglishStrings().aboutNeverBody,
      contains('never sends a message for you'),
    );
  });

  testWidgets('the licence and the source are both on the screen', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.text(const EnglishStrings().aboutLicenseTitle), findsOneWidget);
    expect(find.textContaining('Affero'), findsWidgets);
    // Selectable, so the url can be copied out of the app it describes.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == AppInfo.sourceUrl,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a bengali session gets the about screen in bengali', (
    tester,
  ) async {
    await pumpAbout(tester, language: 'bn');

    expect(find.text(const BengaliStrings().aboutTitle), findsOneWidget);
    expect(find.text(const BengaliStrings().statusDevelopment), findsOneWidget);
    // The English originals must not survive next to their translations.
    expect(find.text(const EnglishStrings().aboutStatusTitle), findsNothing);
    expect(find.text(const EnglishStrings().statusDevelopment), findsNothing);
    // A version is a number in every language.
    expect(find.text('ভার্সন ${AppInfo.versionLabel}'), findsOneWidget);
  });

  testWidgets('a narrow phone in bengali does not overflow', (tester) async {
    // The Bengali strings are the longest ones in the file, and 320dp is the
    // narrowest screen this app targets. A tidy screen is one that survives
    // both, so this asserts the absence of the real symptom: a layout
    // exception, not a comment in a diff.
    SharedPreferences.setMockInitialValues({
      AppConstants.prefAppLanguage: 'bn',
    });
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AboutScreen())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(const BengaliStrings().aboutTitle), findsOneWidget);
  });

  testWidgets('large text sizes do not break the layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AboutScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
