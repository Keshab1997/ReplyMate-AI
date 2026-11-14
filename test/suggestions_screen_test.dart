import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/providers/saved_replies_provider.dart';
import 'package:replymate/features/reply/presentation/suggestions_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

CapturedNotification contextWith({required bool hasReplyAction}) =>
    CapturedNotification(
      packageName: 'com.whatsapp',
      key: 'sbn-1',
      title: 'Asha',
      text: 'Can we meet tomorrow?',
      isTruncated: false,
      isGrouped: false,
      isGroupSummary: false,
      mayBeRedacted: false,
      hasReplyAction: hasReplyAction,
      replyActionLabel: hasReplyAction ? 'Reply' : null,
      postedAtMillis: 0,
    );

const request = ReplyRequest(
  message: 'Can we meet tomorrow?',
  language: ReplyLanguage.english,
  tone: ReplyTone.polite,
  length: ReplyLength.short,
);

class RefiningRepositoryFake implements ReplyRepository {
  ReplyRequest? lastRequest;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    lastRequest = request;
    return const ReplySuccess(['A shorter reply.']);
  }
}

Widget app(Widget screen) => ProviderScope(child: MaterialApp(home: screen));

/// Outbound calls on the bridge channel hang in widget tests when the app has
/// registered an inbound handler on the same channel but no mock exists.
/// shareText answers true; there is no send path left to mock.
const MethodChannel bridgeChannel = MethodChannel(
  'com.keshabstudios.replymate/notifications',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;
  Map<Object?, Object?>? shareArgs;
  var shareAvailable = true;

  setUp(() {
    shareArgs = null;
    shareAvailable = true;
    // Capture Clipboard.setData instead of touching a real clipboard.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bridgeChannel, (
      call,
    ) async {
      switch (call.method) {
        case 'shareText':
          shareArgs = call.arguments as Map<Object?, Object?>;
          return shareAvailable;
        case 'isListenerEnabled':
          return false;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      null,
    );
  });

  testWidgets('copy puts the suggestion on the clipboard', (tester) async {
    clipboardText = null;
    await tester.pumpWidget(
      app(SuggestionsScreen(replies: const ['Sure!'], request: request)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboardText, 'Sure!');
    expect(find.text('Reply copied.'), findsOneWidget);
  });

  testWidgets('share sends the edited suggestion to the chooser', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(SuggestionsScreen(replies: const ['Sure!'], request: request)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Edited reply');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(shareArgs?['text'], 'Edited reply');
    expect(
      find.text('Share sheet opened. Choose an app to continue.'),
      findsOneWidget,
    );
  });

  testWidgets('share failure offers a copy fallback', (tester) async {
    shareAvailable = false;
    await tester.pumpWidget(
      app(SuggestionsScreen(replies: const ['Sure!'], request: request)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sharing is unavailable here. Copy the reply instead.'),
      findsOneWidget,
    );
  });

  testWidgets('a user can refine a draft without replacing its meaning', (
    tester,
  ) async {
    final repository = RefiningRepositoryFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [replyRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: SuggestionsScreen(
            replies: const ['Sure, I can do that.'],
            request: request,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make shorter'));
    await tester.pumpAndSettle();

    expect(
      repository.lastRequest?.trimmedDraftToRefine,
      'Sure, I can do that.',
    );
    expect(repository.lastRequest?.refinementInstruction, contains('shorter'));
    expect(find.text('A shorter reply.'), findsOneWidget);
  });

  testWidgets(
    'keep-conversation action uses available context and one question',
    (tester) async {
      final repository = RefiningRepositoryFake();
      const contextualRequest = ReplyRequest(
        message: 'Can we meet tomorrow?',
        language: ReplyLanguage.english,
        tone: ReplyTone.casual,
        length: ReplyLength.medium,
        priorMessages: ['Friend: Friday works for me.'],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [replyRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: SuggestionsScreen(
              replies: const ['Sure, what time works for you?'],
              request: contextualRequest,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep conversation going'));
      await tester.pumpAndSettle();

      expect(
        repository.lastRequest?.priorMessages,
        contextualRequest.priorMessages,
      );
      expect(repository.lastRequest?.tone, ReplyTone.casual);
      expect(
        repository.lastRequest?.refinementInstruction,
        contains('at most one concise, relevant question'),
      );
      expect(
        repository.lastRequest?.refinementInstruction,
        contains('return the original draft unchanged'),
      );
    },
  );

  testWidgets('a suggestion can be saved as a local template', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SuggestionsScreen(replies: const ['Sure!'], request: request),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as template'));
    await tester.pumpAndSettle();

    expect(container.read(savedRepliesProvider), ['Sure!']);
    expect(find.text('Reply saved to your templates.'), findsOneWidget);
  });

  testWidgets('edit swaps the card text for an editable field', (tester) async {
    await tester.pumpWidget(
      app(SuggestionsScreen(replies: const ['Sure!'], request: request)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Sure!');
    expect(find.text('Done'), findsOneWidget);
  });
}
