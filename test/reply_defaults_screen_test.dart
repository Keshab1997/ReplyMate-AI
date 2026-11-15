import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/settings/presentation/reply_defaults_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The first version of this screen gave every chip in a group the same icon:
/// seven tones, seven identical mood faces. That is a picture of a list, not a
/// way to read one - so "one glyph per option" is now an invariant, and these
/// tests hold it.
void main() {
  group('each option gets its own glyph', () {
    test('no two tones share an icon', () {
      final icons = ReplyTone.values.map(toneIcon).toSet();
      expect(
        icons.length,
        ReplyTone.values.length,
        reason: 'two tones render the same glyph, so the row cannot be read',
      );
    });

    test('no two lengths share an icon', () {
      final icons = ReplyLength.values.map(lengthIcon).toSet();
      expect(icons.length, ReplyLength.values.length);
    });

    test('every draft count is its own number', () {
      final icons = <IconData>{
        for (
          var count = AppConstants.minSuggestionCount;
          count <= AppConstants.maxSuggestionCount;
          count++
        )
          countIcon(count),
      };
      expect(
        icons.length,
        AppConstants.maxSuggestionCount - AppConstants.minSuggestionCount + 1,
      );
    });

    test('the two partner voices are distinct from each other', () {
      // Filled against hollow heart: they are a persona, not a register, and a
      // user choosing between them needs to see which is which.
      expect(toneIcon(ReplyTone.premika), isNot(toneIcon(ReplyTone.premik)));
    });
  });

  group('the screen states the live choice next to each group', () {
    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefDefaultLanguage: 'bn',
        AppConstants.prefDefaultTone: 'professional',
        AppConstants.prefDefaultLength: 'medium',
        AppConstants.prefSuggestionCount: 2,
      });
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ReplyDefaultsScreen())),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every group carries its current value', (tester) async {
      await pump(tester);
      const strings = EnglishStrings();

      expect(find.text(strings.languageLabel), findsOneWidget);
      expect(find.text(strings.toneLabel), findsOneWidget);
      expect(find.text(strings.lengthLabel), findsOneWidget);
      expect(find.text(strings.howManyOptions), findsOneWidget);

      // Twice each: once as the chip that is live, once as the value beside the
      // label. The pair is the feature - with ten chips on screen, finding the
      // live one should not mean hunting for a tint.
      expect(find.text(ReplyTone.professional.label), findsNWidgets(2));
      expect(find.text(ReplyLength.medium.label), findsNWidgets(2));
      expect(find.text(ReplyLanguage.bengali.label), findsNWidgets(2));
      expect(find.text('2'), findsNWidgets(2));
    });

    testWidgets('every tone is offered, not only the first five', (
      tester,
    ) async {
      await pump(tester);
      for (final tone in ReplyTone.values) {
        expect(
          find.text(tone.label),
          findsAtLeast(1),
          reason: 'tone missing from the selector: ${tone.label}',
        );
      }
    });

    testWidgets('a narrow phone in bengali does not overflow', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefAppLanguage: 'bn',
        AppConstants.prefDefaultTone: 'shortAndDirect',
      });
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ReplyDefaultsScreen())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
