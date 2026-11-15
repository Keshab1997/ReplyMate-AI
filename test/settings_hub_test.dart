import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/about/about_screen.dart';
import 'package:replymate/features/settings/presentation/appearance_screen.dart';
import 'package:replymate/features/settings/presentation/reply_defaults_screen.dart';
import 'package:replymate/features/settings/presentation/settings_tile.dart';
import 'package:replymate/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings is a hub now, so what it must get right changed: every door exists,
/// each door opens, and the hub itself holds no controls. The controls have
/// their own tests, on their own screens.
Future<void> pumpHub(WidgetTester tester, {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? <String, Object>{});
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: SettingsScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every section has a named door with an icon', (tester) async {
    await pumpHub(tester);
    const strings = EnglishStrings();

    expect(find.byType(SettingsTile), findsNWidgets(7));
    for (final title in <String>[
      strings.replyStyle,
      strings.captureSection,
      strings.ownKeySection,
      strings.conversationMemorySection,
      strings.privacySection,
      strings.appearanceTitle,
      strings.aboutOpenTitle,
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing door: $title');
    }
  });

  testWidgets('the hub states the current reply style, not a hint', (
    tester,
  ) async {
    await pumpHub(
      tester,
      prefs: <String, Object>{
        AppConstants.prefDefaultLanguage: 'bn',
        AppConstants.prefDefaultTone: 'professional',
        AppConstants.prefDefaultLength: 'medium',
        AppConstants.prefSuggestionCount: 2,
      },
    );

    // Readable before the tap: this is the whole point of a summary line.
    final summary =
        '${ReplyLanguage.bengali.label} · ${ReplyTone.professional.label} · '
        '${ReplyLength.medium.label} · 2';
    expect(find.text(summary), findsOneWidget);
  });

  testWidgets('the appearance door opens color and brightness choices', (
    tester,
  ) async {
    await pumpHub(tester);

    await tester.tap(find.text(const EnglishStrings().appearanceTitle));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceScreen), findsOneWidget);
    expect(find.text(const EnglishStrings().paletteViolet), findsOneWidget);
    expect(find.text(const EnglishStrings().paletteForest), findsOneWidget);
    expect(find.text(const EnglishStrings().appearanceSystem), findsOneWidget);
  });

  testWidgets('the hub holds no controls of its own', (tester) async {
    await pumpHub(tester);

    // The chips, switches and buttons all live behind a door now. A hub that
    // still carried one of them would be the old long screen growing back.
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the reply-defaults door opens that screen', (tester) async {
    await pumpHub(tester);

    await tester.tap(find.text(const EnglishStrings().replyStyle));
    await tester.pumpAndSettle();

    expect(find.byType(ReplyDefaultsScreen), findsOneWidget);
    // The four chip groups are there, with a way back.
    expect(find.text(const EnglishStrings().toneLabel), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('the about door opens the about screen', (tester) async {
    await pumpHub(tester);

    await tester.tap(find.text(const EnglishStrings().aboutOpenTitle));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text(const EnglishStrings().aboutStatusTitle), findsOneWidget);
  });

  testWidgets('the hub survives a narrow phone in bengali', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.prefAppLanguage: 'bn',
    });
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsTile), findsNWidgets(7));
  });
}
