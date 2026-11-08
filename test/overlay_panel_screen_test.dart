import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/overlay/models/overlay_context.dart';
import 'package:replymate/features/overlay/presentation/overlay_panel_screen.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures what the panel asked for, so a test can prove which text was sent.
class _RecordingRepository implements ReplyRepository {
  ReplyRequest? request;

  @override
  Future<ReplyResult> generate(ReplyRequest request) async {
    this.request = request;
    return const ReplyFailure('Recorded.');
  }
}

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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;

  setUp(() {
    clipboard = null;
    // The system clipboard, in one place: writes land in `clipboard`, reads
    // answer from it. Anything else on the platform channel is ignored.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return clipboard == null
                ? null
                : <String, Object?>{'text': clipboard};
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<void> pumpPanel(
    WidgetTester tester,
    OverlayContext context, {
    Map<String, Object> prefs = const <String, Object>{},
    List<Override> overrides = const <Override>[],
  }) async {
    // Set per test, not once: the style row reads these.
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
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

  testWidgets('copy puts the captured message on the clipboard', (
    tester,
  ) async {
    await pumpPanel(tester, _context());

    await tester.ensureVisible(find.text('Copy'));
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(clipboard, 'Can we meet tomorrow?');
  });

  testWidgets('a pasted message is what actually gets generated', (
    tester,
  ) async {
    // The on-screen notification carried nothing usable; the user pastes the
    // message instead and expects a reply from exactly that text.
    clipboard = 'Pasted from the chat I am looking at';
    final repository = _RecordingRepository();
    await pumpPanel(
      tester,
      _context(text: ''),
      overrides: [replyRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.ensureVisible(find.text('Paste'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(find.text('Pasted from the chat I am looking at'), findsOneWidget);

    await tester.ensureVisible(find.text('Generate suggestions'));
    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();

    expect(repository.request?.message, 'Pasted from the chat I am looking at');
  });

  testWidgets('the message can be edited by hand before generating', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await pumpPanel(
      tester,
      _context(),
      overrides: [replyRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Edited by hand');
    await tester.ensureVisible(find.text('Generate suggestions'));
    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();

    expect(repository.request?.message, 'Edited by hand');
  });
}
