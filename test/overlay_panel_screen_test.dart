import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/overlay/models/overlay_context.dart';
import 'package:replymate/features/overlay/presentation/overlay_panel_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

OverlayContext _context({bool hasReplyAction = true, String? text}) =>
    OverlayContext.fromMap(<Object?, Object?>{
      'source': 'bubble',
      'packageName': 'com.whatsapp',
      'key': 'sbn-7',
      'title': 'Asha',
      'text': text ?? 'Can we meet tomorrow?',
      'isTruncated': false,
      'isGrouped': false,
      'isGroupSummary': false,
      'mayBeRedacted': false,
      'hasReplyAction': hasReplyAction,
      'replyActionLabel': hasReplyAction ? 'Reply' : null,
      'postedAtMillis': 1,
    });

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    OverlayContext context, {
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    // Set per test, not once: the style row reads these.
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: OverlayPanelScreen(initialContext: context)),
      ),
    );
    await tester.pumpAndSettle();
    // The saved style is read asynchronously from SharedPreferences; give it a
    // frame to land before the assertions look at the style row.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  testWidgets('a stubbed context renders the message and its app', (
    tester,
  ) async {
    await pumpPanel(tester, _context());

    expect(find.text('via WhatsApp'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Can we meet tomorrow?'), findsOneWidget);
    expect(find.text('Generate suggestions'), findsOneWidget);
  });

  testWidgets('the panel asks nothing the main app already knows', (
    tester,
  ) async {
    // Language / tone / length are Settings' business. The panel shows the
    // saved choice and links to it - it must not re-ask per message.
    await pumpPanel(
      tester,
      _context(),
      prefs: const <String, Object>{
        AppConstants.prefDefaultLanguage: 'bn',
        AppConstants.prefDefaultTone: 'professional',
        AppConstants.prefDefaultLength: 'medium',
      },
    );

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Bengali · Professional · Medium'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    // The way out to those controls is the tune icon.
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('a complete message shows no warning noise', (tester) async {
    await pumpPanel(tester, _context());
    expect(find.textContaining('grouped'), findsNothing);
    expect(find.textContaining('redacted'), findsNothing);
  });

  testWidgets('guest mode explains itself instead of inventing a reply', (
    tester,
  ) async {
    // No firebaseReadyProvider override: guest mode, as shipped.
    await pumpPanel(tester, _context());
    expect(find.textContaining('not configured'), findsOneWidget);

    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();
    // The failure is shown in the panel; nothing pretends to be a suggestion.
    expect(find.textContaining('not configured'), findsWidgets);
  });

  testWidgets('a notification without a reply action offers no quick reply', (
    tester,
  ) async {
    await pumpPanel(tester, _context(hasReplyAction: false));
    expect(find.text('Quick reply'), findsNothing);
  });

  testWidgets('a message with no text says so rather than showing a shell', (
    tester,
  ) async {
    await pumpPanel(tester, _context(text: ''));
    expect(find.textContaining('exposed no message text'), findsOneWidget);
  });
}
