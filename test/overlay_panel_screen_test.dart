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
  int calls = 0;

  @override
  Future<ReplyResult> generate(ReplyRequest request) async {
    calls++;
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
    bool highContrast = false,
    bool disableAnimations = false,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    // Set per test, not once: the style row reads these.
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              highContrast: highContrast,
              disableAnimations: disableAnimations,
              viewInsets: viewInsets,
            ),
            child: child!,
          ),
          home: OverlayPanelScreen(initialContext: context),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The saved style is read asynchronously from SharedPreferences; give it a
    // frame to land before the assertions look at the style row.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  testWidgets('the reply surface is a centered glass card, not a sheet', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPanel(tester, _context());

    final card = find.byKey(const Key('overlayGlassCard'));
    expect(card, findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(tester.getCenter(card), const Offset(540, 1200));
    expect(tester.getSize(card).width, lessThanOrEqualTo(460));
    expect(
      tester.getSemantics(find.byKey(const Key('overlayPanelSemantics'))),
      matchesSemantics(label: 'ReplyMate floating reply panel'),
    );
    semantics.dispose();
  });

  testWidgets('the glass card stays above the keyboard', (tester) async {
    await pumpPanel(
      tester,
      _context(),
      viewInsets: const EdgeInsets.only(bottom: 600),
    );

    final rect = tester.getRect(find.byKey(const Key('overlayGlassCard')));
    expect(rect.bottom, lessThanOrEqualTo(1800));
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('high contrast replaces blur with a solid surface', (
    tester,
  ) async {
    await pumpPanel(tester, _context(), highContrast: true);

    expect(find.byKey(const Key('overlaySolidBackdrop')), findsOneWidget);
    expect(find.byKey(const Key('overlayBlurredBackdrop')), findsNothing);
    expect(find.text('Generate a reply'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('overlayGlassCard'))).width,
      lessThanOrEqualTo(460),
    );
  });

  testWidgets('reduced motion skips the floating entrance animation', (
    tester,
  ) async {
    await pumpPanel(tester, _context(), disableAnimations: true);

    final entrance = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    final keyboard = tester.widget<AnimatedPadding>(
      find.byType(AnimatedPadding),
    );
    expect(entrance.duration, Duration.zero);
    expect(keyboard.duration, Duration.zero);
    expect(
      tester.getCenter(find.byKey(const Key('overlayGlassCard'))),
      const Offset(540, 1200),
    );
  });

  testWidgets('a stubbed context renders the message and its app', (
    tester,
  ) async {
    await pumpPanel(tester, _context());

    expect(find.text('via WhatsApp'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Can we meet tomorrow?'), findsOneWidget);
    // Nothing is generated until the user asks: opening the panel is not a
    // decision to spend a request on the model behind it.
    expect(find.text('Generate a reply'), findsOneWidget);
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
    // No firebaseReadyProvider override: guest mode, as shipped. The banner is
    // up before anything is spent, so this install says it cannot generate
    // rather than letting the user find out from a failure.
    await pumpPanel(tester, _context());
    expect(find.textContaining('not configured'), findsWidgets);

    await tester.tap(find.text('Generate a reply'));
    await tester.pumpAndSettle();
    // The failure is shown in the panel; nothing pretends to be a suggestion.
    expect(find.textContaining('not configured'), findsWidgets);
  });

  testWidgets('the panel never offers to send anything on its own', (
    tester,
  ) async {
    // Quick reply is gone: the button did not work, and a send affordance that
    // cannot send is worse than none. Copy and share are the whole offer.
    await pumpPanel(tester, _context(hasReplyAction: false));
    expect(find.text('Quick reply'), findsNothing);
    expect(find.byIcon(Icons.send_rounded), findsNothing);
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
    // Nothing was generated on the way in - there was nothing to draft from,
    // and guessing would have been worse.
    expect(repository.request, isNull);

    await tester.ensureVisible(find.text('Generate a reply'));
    await tester.tap(find.text('Generate a reply'));
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
    await tester.ensureVisible(find.text('Generate a reply'));
    await tester.tap(find.text('Generate a reply'));
    await tester.pumpAndSettle();

    expect(repository.request?.message, 'Edited by hand');
  });

  testWidgets('a second waiting chat can be picked from the switcher', (
    tester,
  ) async {
    // Three chats can ping you while the bubble is up. Before this, the badge
    // counted them and the panel could only ever answer the last one.
    const channel = MethodChannel(AppConstants.channelName);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'peekOverlayContexts') return null;
      return <Map<String, Object?>>[
        <String, Object?>{
          'source': 'bubble',
          'packageName': 'com.whatsapp',
          'key': 'sbn-2',
          'title': 'Office group',
          'text': 'Standup at 10?',
          'isTruncated': false,
          'isGrouped': false,
          'isGroupSummary': false,
          'mayBeRedacted': false,
          'hasReplyAction': true,
          'replyActionLabel': 'Reply',
          'postedAtMillis': 2,
        },
      ];
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final repository = _RecordingRepository();
    await pumpPanel(
      tester,
      _context(),
      overrides: [replyRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text('Office group'), findsOneWidget);

    await tester.tap(find.text('Office group'));
    await tester.pumpAndSettle();

    expect(find.text('Standup at 10?'), findsOneWidget);
    expect(find.text('Can we meet tomorrow?'), findsNothing);
    // Switching chats is not a request either: nothing is generated for either
    // conversation until the button is pressed.
    expect(repository.request, isNull);
    await tester.ensureVisible(find.text('Generate a reply'));
    await tester.tap(find.text('Generate a reply'));
    await tester.pumpAndSettle();
    // The reply is for the chat now on screen, not the one left behind.
    expect(repository.request?.message, 'Standup at 10?');
  });

  testWidgets('nothing is generated until the user asks', (tester) async {
    // Drafting on open was tried and taken back: opening the bubble is not the
    // same decision as spending a request on the model behind it.
    final repository = _RecordingRepository();
    await pumpPanel(
      tester,
      _context(),
      overrides: [replyRepositoryProvider.overrideWithValue(repository)],
    );

    expect(repository.calls, 0);

    await tester.tap(find.text('Generate a reply'));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.request?.message, 'Can we meet tomorrow?');
  });

  testWidgets('one suggestion is asked for by default', (tester) async {
    // Comparing three paragraphs is more work than editing the one you would
    // have picked anyway, so one is the default and Settings can raise it.
    final repository = _RecordingRepository();
    await pumpPanel(
      tester,
      _context(),
      overrides: [replyRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.tap(find.text('Generate a reply'));
    await tester.pumpAndSettle();

    expect(repository.request?.count, 1);
  });

  testWidgets('a rebuild does not spend a second request on the same message', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await pumpPanel(
      tester,
      _context(),
      overrides: [replyRepositoryProvider.overrideWithValue(repository)],
    );
    await tester.tap(find.text('Generate a reply'));
    await tester.pumpAndSettle();

    // One request, asked for once. A rebuild - a style change, a keyboard - is
    // not a second instruction to generate.
    expect(repository.calls, 1);
  });
}
