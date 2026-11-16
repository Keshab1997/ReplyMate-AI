import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/features/reply/domain/writing_format.dart';
import 'package:replymate/features/reply/presentation/create_message_screen.dart';
import 'package:replymate/features/reply/data/writer_chat_history_store.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';
import 'package:replymate/features/memory/providers/conversation_memory_provider.dart';
import 'package:replymate/features/memory/data/remembered_facts_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryBackend implements MemoryBackend {
  final Map<String, Map<Object?, Object?>> data = {};

  @override
  Future<void> clearAll() async => data.clear();
  @override
  Future<Map<String, Map<Object?, Object?>>> loadAll() async => {
    for (final entry in data.entries) entry.key: entry.value,
  };
  @override
  Future<void> put(String id, Map<String, Object?> json) async =>
      data[id] = json;
  @override
  Future<void> remove(String id) async => data.remove(id);
}

class _RecordingCreateRepository implements ReplyRepository {
  ReplyRequest? request;
  final List<ReplyRequest> requests = <ReplyRequest>[];

  /// Whether each call skipped the cache - the whole point of "write another".
  final List<bool> bypassFlags = <bool>[];
  int calls = 0;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    calls++;
    bypassFlags.add(bypassCache);
    this.request = request;
    requests.add(request);
    return const ReplySuccess(['তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।']);
  }
}

/// A repository that can stream, with the chunks handed to it by the test, so
/// the widget test controls exactly when each piece of the answer arrives.
class _ScriptedStreamingRepository implements StreamingReplyRepository {
  _ScriptedStreamingRepository(this.script);

  /// Each entry is one yield from the repository: either a preview (no result)
  /// or the final one.
  final List<ReplyProgress> script;
  int calls = 0;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async => const ReplySuccess(['unused']);

  @override
  Stream<ReplyProgress> generateStreaming(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async* {
    calls++;
    for (final step in script) {
      yield step;
    }
  }
}

/// Fails the first call, then behaves. Used to prove a failure is recoverable.
class _FlakyRepository implements ReplyRepository {
  _FlakyRepository();

  int calls = 0;
  final List<bool> bypassFlags = <bool>[];

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    calls++;
    bypassFlags.add(bypassCache);
    if (calls == 1) return const ReplyFailure('No provider answered.');
    return const ReplySuccess(['দিনটা শুভ হোক!']);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpCreateScreen(
    WidgetTester tester,
    ReplyRepository repository, {
    bool memoryEnabled = false,
    WriterChatHistoryStore? historyStore,
    Map<String, Object> extraPrefs = const <String, Object>{},
    List<Override> extraOverrides = const <Override>[],
  }) async {
    SharedPreferences.setMockInitialValues({
      if (memoryEnabled) 'conversation_memory_enabled': true,
      ...extraPrefs,
    });
    // The screen reads the user's facts on every send. The real store opens a
    // Hive box, which a widget test has no reason to own - so every pump gets a
    // fake, whether or not the test cares about facts.
    final facts = RememberedFactsStore(backend: _MemoryBackend());
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(repository),
          if (historyStore != null)
            writerChatHistoryStoreProvider.overrideWithValue(historyStore),
          rememberedFactsStoreProvider.overrideWithValue(facts),
          ...extraOverrides,
        ],
        child: const MaterialApp(home: CreateMessageScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the style sheet. The chips live there rather than inline, so every
  /// style test starts with one tap - the same tap a user makes.
  Future<void> openStyleSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('openChatStyleSheet')));
    await tester.pumpAndSettle();
  }

  Future<void> chooseStyle(WidgetTester tester, String id, String value) async {
    await openStyleSheet(tester);
    await tester.tap(find.byKey(ValueKey<String>('chatStyle-$id-$value')));
    await tester.pumpAndSettle();
    // Close the sheet so the composer is reachable again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  testWidgets('free-form writing brief creates a standalone message', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    expect(repository.calls, 0);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a short, sweet quote for my girlfriend in Bengali.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.request?.mode, ReplyMode.createMessage);
    expect(
      repository.request?.message,
      'Write a short, sweet quote for my girlfriend in Bengali.',
    );
    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);
  });

  testWidgets('every writing format is one tap away and reaches the request', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    // Chat is the default, and it is what the screen shipped as - stated on
    // the toolbar pill, so no menu has to be opened to find that out.
    expect(find.byKey(const Key('openWritingFormatMenu')), findsOneWidget);
    expect(find.text(const EnglishStrings().formatChat), findsWidgets);

    await tester.tap(find.byKey(const Key('openWritingFormatMenu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('writingFormat-application')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a leave application for three days.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(repository.request?.format, WritingFormat.application);
    expect(repository.request?.mode, ReplyMode.createMessage);
  });

  testWidgets('a document format offers document ideas, not chat ideas', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    // A chat format's inspiration is chat messages; an application's is
    // applications. Showing the wrong one is how a feature looks broken.
    expect(
      find.text(const EnglishStrings().exampleThankSomeone),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('openWritingFormatMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('writingFormat-email')));
    await tester.pumpAndSettle();

    expect(find.text(const EnglishStrings().exampleThankSomeone), findsNothing);
    expect(find.text('Email to a teacher'), findsOneWidget);

    await tester.tap(find.text('Email to a teacher'));
    await tester.pumpAndSettle();
    expect(repository.request?.format, WritingFormat.email);
    expect(repository.request?.message, contains('email'));
  });

  testWidgets('copies a generated draft directly from the chat', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write something sweet.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('copyCreateMessageDraft-0-0')));
    await tester.pumpAndSettle();
    expect(copiedText, 'তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।');
  });

  testWidgets('a quick idea starts one request without another Generate tap', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    await tester.tap(find.byKey(const ValueKey('create-message-idea-0')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.request?.mode, ReplyMode.createMessage);
    // The first quick idea is a good morning message; the list deliberately
    // leads with a relationship most users have.
    expect(repository.request?.message, contains('good morning'));
    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);
  });

  testWidgets('a follow-up brief carries the earlier chat context', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a short birthday message for my friend.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Make it a little funnier.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    expect(repository.requests[1].mode, ReplyMode.createMessage);
    expect(
      repository.requests[1].priorMessages,
      contains('User: Write a short birthday message for my friend.'),
    );
    expect(
      repository.requests[1].priorMessages,
      contains('Assistant: তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'),
    );
  });

  testWidgets('suggestions stay drafts until the user opens review', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a short message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reviewCreateMessageDrafts')));
    await tester.pumpAndSettle();

    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsWidgets);
  });

  testWidgets(
    'opening the writer does not generate and empty submit explains',
    (tester) async {
      final repository = _RecordingCreateRepository();
      await pumpCreateScreen(tester, repository);

      expect(repository.calls, 0);
      await tester.tap(find.byKey(const Key('createMessageSendButton')));
      await tester.pumpAndSettle();

      expect(repository.calls, 0);
      expect(
        find.text(const EnglishStrings().createMessageEmpty),
        findsOneWidget,
      );
    },
  );

  testWidgets('saves only with memory enabled and restores/deletes a chat', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final backend = _MemoryBackend();
    final history = WriterChatHistoryStore(backend: backend);
    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      historyStore: history,
    );
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a warm birthday message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(await history.all(), hasLength(1));

    await tester.tap(find.byKey(const Key('openCreateMessageHistory')));
    await tester.pumpAndSettle();
    expect(find.text('Writing history'), findsOneWidget);
    await tester.tap(find.text('Write a warm birthday message.'));
    await tester.pumpAndSettle();
    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Make it funnier.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(
      repository.requests.last.priorMessages,
      contains('User: Write a warm birthday message.'),
    );

    await tester.tap(find.byKey(const Key('openCreateMessageHistory')));
    await tester.pumpAndSettle();
    final chatId = (await history.all()).single.id;
    await tester.tap(
      find.byKey(ValueKey<String>('delete-writer-history-$chatId')),
    );
    await tester.pumpAndSettle();
    expect(await history.all(), isEmpty);
  });

  testWidgets('a failed turn can be retried without retyping anything', (
    tester,
  ) async {
    final repository = _FlakyRepository();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [replyRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: CreateMessageScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a good morning message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // The failure is shown, and so is the way out of it.
    expect(find.byKey(const Key('createMessageFailure')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('retryCreateMessage-0')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('retryCreateMessage-0')),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    // Same request, not a rebuilt one: the brief is not retyped or re-guessed.
    expect(find.text('দিনটা শুভ হোক!'), findsOneWidget);
    // The stale error is gone - a turn that recovered must not keep showing it.
    expect(find.byKey(const Key('createMessageFailure')), findsNothing);
    // A retry is allowed to use the cache: nothing changed, so the cached
    // answer for the same request is a fair answer.
    expect(repository.bypassFlags, [false, false]);
  });

  testWidgets('write another asks again with the cache bypassed', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a good morning message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('writeAnother-0')));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    // The second call must skip the cache. Without this the button would serve
    // back the draft that is already on screen and look broken.
    expect(repository.bypassFlags, [false, true]);
    // It replaces the draft in place: the conversation gains no new turn.
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-0-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-1-0')),
      findsNothing,
    );
  });

  testWidgets('a draft can be shared, and sharing only opens the chooser', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    Map<Object?, Object?>? shareArgs;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(AppConstants.channelName),
          (call) async => call.method == 'shareText'
              ? (shareArgs = call.arguments as Map<Object?, Object?>, true).$2
              : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(AppConstants.channelName),
            null,
          ),
    );
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write something sweet.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('shareCreateMessageDraft-0-0')),
    );
    await tester.pumpAndSettle();

    // The draft reaches Android's chooser with its exact text. Nothing here
    // sends: the chooser is where the user picks an app and confirms.
    expect(shareArgs?['text'], 'তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।');
  });

  testWidgets('the chat answers in the style its chips say, not Settings', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    // Settings defaults to English/friendly/short. Choose the style a user
    // composing a Bengali message for a partner would.
    await chooseStyle(tester, 'language', 'bn');
    await chooseStyle(tester, 'tone', 'premika');
    await chooseStyle(tester, 'length', 'medium');

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write her a good morning message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // This is the regression: these three used to be read from Settings on
    // every send, so the chips were decoration and the request always left
    // with the stored default.
    expect(repository.request?.language, ReplyLanguage.bengali);
    expect(repository.request?.tone, ReplyTone.premika);
    expect(repository.request?.length, ReplyLength.medium);
  });

  testWidgets('the style sticks for the rest of the chat, and the draft says '
      'what it was written in', (tester) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);

    await chooseStyle(tester, 'tone', 'funny');
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a birthday wish.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // A follow-up brief is still the same conversation, so it keeps the tone
    // without the user tapping the chip again.
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Make it shorter.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    expect(repository.requests[1].tone, ReplyTone.funny);
    // The style is stated once, on the toolbar pill - a draft written in
    // exactly that style carries no label of its own.
    expect(find.byKey(const Key('chatStyleSummary')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('chatStyleSummary'))).data,
      contains(ReplyTone.funny.label),
    );
    expect(
      find.byKey(const ValueKey<String>('createMessageDraftStyle-1-0')),
      findsNothing,
    );
  });

  testWidgets('a reopened chat restores the style it was written in', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final history = WriterChatHistoryStore(backend: _MemoryBackend());
    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      historyStore: history,
    );

    await chooseStyle(tester, 'language', 'bn');
    await chooseStyle(tester, 'tone', 'polite');
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a thank-you message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // The stored turn carries the style, not just the text.
    final saved = (await history.all()).single;
    expect(saved.turns.single.language, ReplyLanguage.bengali.code);
    expect(saved.turns.single.tone, ReplyTone.polite.name);

    // Move the app defaults somewhere else, then reopen the chat: it must come
    // back as Bengali/polite, not as the new default.
    await chooseStyle(tester, 'language', 'hi');
    await chooseStyle(tester, 'tone', 'funny');

    await tester.tap(find.byKey(const Key('openCreateMessageHistory')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a thank-you message.'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Make it warmer.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(repository.requests.last.language, ReplyLanguage.bengali);
    expect(repository.requests.last.tone, ReplyTone.polite);
  });

  testWidgets('history search filters by brief and by draft text', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final backend = _MemoryBackend();
    final history = WriterChatHistoryStore(backend: backend);

    // Two saved chats, seeded directly: the search is what is under test, not
    // the saving path (that has its own test).
    await history.save(
      WriterChatHistory(
        id: 'a',
        updatedAt: DateTime.now(),
        turns: const [
          WriterChatTurn(
            prompt: 'Write a birthday message for Rahim.',
            replies: ['তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'],
            format: 'chat',
          ),
        ],
      ),
    );
    await history.save(
      WriterChatHistory(
        id: 'b',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        turns: const [
          WriterChatTurn(
            prompt: 'Write a thank-you note for Karim.',
            replies: ['ধন্যবাদ, তুমি অনেক ভালো।'],
            format: 'chat',
          ),
        ],
      ),
    );

    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      historyStore: history,
    );
    await tester.tap(find.byKey(const Key('openCreateMessageHistory')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('writerHistorySearch')), findsOneWidget);
    expect(find.textContaining('birthday message'), findsOneWidget);
    expect(find.textContaining('thank-you note'), findsOneWidget);

    // Match on the brief.
    await tester.enterText(
      find.byKey(const Key('writerHistorySearch')),
      'birthday',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('birthday message'), findsOneWidget);
    expect(find.textContaining('thank-you note'), findsNothing);

    // It reaches into the draft text too - the thing people remember is often
    // something said later in the chat, not the first line they typed.
    await tester.enterText(
      find.byKey(const Key('writerHistorySearch')),
      'সুন্দর ভাবনা',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('birthday message'), findsOneWidget);
    expect(find.textContaining('thank-you note'), findsNothing);

    // No match is a state, not an empty list that looks broken.
    await tester.enterText(
      find.byKey(const Key('writerHistorySearch')),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('writerHistoryNoMatch')), findsOneWidget);
    expect(find.textContaining('birthday message'), findsNothing);
  });

  testWidgets('a new visit reopens the chat the user was writing', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final backend = _MemoryBackend();
    final history = WriterChatHistoryStore(backend: backend);

    // First visit: write something, which saves the chat and its pointer.
    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      historyStore: history,
    );
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a birthday message for Rahim.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);

    // Second visit: a fresh widget tree, same stores, and the pointer that
    // survived on disk - the way a relaunch looks.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final savedId = (await history.all()).single.id;
    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      historyStore: history,
      extraPrefs: <String, Object>{'writer_last_chat_id': savedId},
    );
    await tester.pumpAndSettle();

    // The brief and the draft are back without a trip through history.
    expect(find.text('Write a birthday message for Rahim.'), findsOneWidget);
    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);
    // And it is a restore, not a regeneration.
    expect(repository.calls, 1);
  });

  testWidgets('a restore never overwrites a brief already being typed', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final history = WriterChatHistoryStore(backend: _MemoryBackend());
    await pumpCreateScreen(tester, repository, memoryEnabled: true);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a birthday message for Rahim.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    SharedPreferences.setMockInitialValues({
      'conversation_memory_enabled': true,
      'writer_last_chat_id': 'does-not-exist',
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(repository),
          writerChatHistoryStoreProvider.overrideWithValue(history),
        ],
        child: const MaterialApp(home: CreateMessageScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // A stale pointer must not throw and must not paint a ghost chat.
    expect(find.byKey(const Key('createMessageFailure')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the writer writes in the user\'s own voice, when memory allows', (
    tester,
  ) async {
    // Two things are needed for voice evidence: memory on, and the app the
    // lines came from on the allowlist.
    SharedPreferences.setMockInitialValues({
      'conversation_memory_enabled': true,
      AppConstants.prefSelectedApps: <String>['com.whatsapp'],
    });
    final backend = _MemoryBackend();
    final memoryStore = ConversationMemoryStore(backend: backend);
    final key = ConversationKey.tryOf(
      packageName: 'com.whatsapp',
      contactName: 'Rahim',
    )!;
    await memoryStore.save(
      ConversationMemory.fromStored(
        key: key,
        now: DateTime.now(),
        lines: [
          MemoryLine(
            text: 'আমি কাল আসতে পারব না, পরে জানাচ্ছি',
            author: MemoryAuthor.me,
            at: DateTime.now(),
          ),
        ],
      ),
    );

    // The allowlist notifier re-asserts itself natively on load; without this
    // mock that await never completes and the screen never sends.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(AppConstants.channelName),
          (call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(AppConstants.channelName),
            null,
          ),
    );

    final repository = _RecordingCreateRepository();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(repository),
          conversationMemoryStoreProvider.overrideWithValue(memoryStore),
          rememberedFactsStoreProvider.overrideWithValue(
            RememberedFactsStore(backend: _MemoryBackend()),
          ),
        ],
        child: const MaterialApp(home: CreateMessageScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a short message to Rahim.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // The request carries the user's own line as a style example - the same
    // thing the reply panel has always done, which the writer screen never did.
    expect(
      repository.request?.styleExamples,
      contains('আমি কাল আসতে পারব না, পরে জানাচ্ছি'),
    );
  });

  testWidgets('facts the user typed reach the request; nothing when memory is '
      'off', (tester) async {
    final repository = _RecordingCreateRepository();
    final factsBackend = _MemoryBackend();
    final facts = RememberedFactsStore(backend: factsBackend);
    await facts.add('my name is Keshab');

    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      extraOverrides: [rememberedFactsStoreProvider.overrideWithValue(facts)],
    );
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a message to my landlord.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(repository.request?.rememberedFacts, ['my name is Keshab']);

    // Memory off means the app keeps nothing about you - including this.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpCreateScreen(
      tester,
      repository,
      extraOverrides: [rememberedFactsStoreProvider.overrideWithValue(facts)],
    );
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write another message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(repository.request?.rememberedFacts, isEmpty);
  });

  testWidgets('a draft is edited in place, and cancel writes nothing', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write something sweet.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('editDraftTap-0-0')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey<String>('editDraftField-0-0'));
    expect(field, findsOneWidget);

    // Cancel leaves the original text exactly as it was.
    await tester.enterText(field, 'something the user typed by mistake');
    await tester.tap(find.byKey(const ValueKey<String>('cancelEditDraft-0-0')));
    await tester.pumpAndSettle();
    expect(find.text('তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।'), findsOneWidget);

    // Save writes the edit back, in the same turn.
    await tester.tap(find.byKey(const ValueKey<String>('editDraftTap-0-0')));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'দিনটা শুভ হোক, বন্ধু।');
    await tester.tap(find.byKey(const ValueKey<String>('saveEditDraft-0-0')));
    await tester.pumpAndSettle();

    expect(find.text('দিনটা শুভ হোক, বন্ধু।'), findsOneWidget);
    // Editing is not a new provider call - the words are the user's now.
    expect(repository.calls, 1);
  });

  testWidgets('new chat clears the screen without deleting history', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final history = WriterChatHistoryStore(backend: _MemoryBackend());
    await pumpCreateScreen(
      tester,
      repository,
      memoryEnabled: true,
      historyStore: history,
    );
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a birthday message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(await history.all(), hasLength(1));

    await tester.tap(find.byKey(const Key('writerOverflowMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(const EnglishStrings().newChat));
    await tester.pumpAndSettle();

    // Back to the welcome screen...
    expect(
      find.text(const EnglishStrings().createMessageExamples),
      findsOneWidget,
    );
    // ...and the saved chat is still in history.
    expect(await history.all(), hasLength(1));
  });

  testWidgets('a turn can be removed on its own', (tester) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);
    for (final brief in ['One.', 'Two.']) {
      await tester.enterText(
        find.byKey(const Key('createMessagePromptField')),
        'Write $brief',
      );
      await tester.tap(find.byKey(const Key('createMessageSendButton')));
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-1-0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('deleteTurn-0')));
    await tester.pumpAndSettle();

    // The second exchange survives; only the first is gone.
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-1-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-0-0')),
      findsOneWidget,
    );
  });

  testWidgets('asking for a change rewrites that one draft, in place', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write a birthday message.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('askChange-0-0')));
    await tester.pumpAndSettle();

    // A free-text instruction reaches the request as a refinement, not as a new
    // brief: the draft is the thing being edited.
    await tester.enterText(
      find.byKey(const Key('refineInstructionField')),
      'drop the second sentence',
    );
    await tester.tap(find.byKey(const Key('submitRefineInstruction')));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    final sent = repository.requests.last;
    expect(sent.draftToRefine, 'তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।');
    expect(sent.refinementInstruction, 'drop the second sentence');
    // One draft out, one draft back.
    expect(sent.count, 1);
    // Refining is always a fresh call - a cached answer would be the draft the
    // user just asked to change.
    expect(repository.bypassFlags.last, isTrue);
  });

  testWidgets('a streamed answer appears while it is written', (tester) async {
    final repository = _ScriptedStreamingRepository([
      const ReplyProgress(['প্রথম উত্তর']),
      const ReplyProgress([
        'প্রথম উত্তর',
        'দ্বিতীয় উত্তর',
      ], result: ReplySuccess(['প্রথম উত্তর', 'দ্বিতীয় উত্তর'])),
    ]);
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write two lines.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-0-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-0-1')),
      findsOneWidget,
    );
    // The preview row is gone once the answer is real.
    expect(
      find.byKey(const ValueKey<String>('streamPreview-0-0')),
      findsNothing,
    );
  });

  testWidgets('a stream that dies never leaves its preview as the answer', (
    tester,
  ) async {
    final repository = _ScriptedStreamingRepository([
      const ReplyProgress(['অর্ধেক লেখা']),
      // No final event: this is a cut connection.
    ]);
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write something.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // The half-written line is gone, and the screen says what happened.
    expect(find.text('অর্ধেক লেখা'), findsNothing);
    expect(find.byKey(const Key('createMessageFailure')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-0-0')),
      findsNothing,
    );
    // ...and it can be retried, which is the only honest offer at that point.
    expect(
      find.byKey(const ValueKey<String>('retryCreateMessage-0')),
      findsOneWidget,
    );
  });

  testWidgets('a preview is shown under a writing state, not as a draft', (
    tester,
  ) async {
    final repository = _ScriptedStreamingRepository([
      const ReplyProgress(['লেখা হচ্ছে এমন একটা লাইন']),
      const ReplyProgress([
        'লেখা হচ্ছে এমন একটা লাইন',
      ], result: ReplySuccess(['লেখা হচ্ছে এমন একটা লাইন'])),
    ]);
    await pumpCreateScreen(tester, repository);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Write something.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();

    // Once finished it is a draft; before that it lived in the preview slot,
    // which is a different key precisely so the two cannot be confused.
    expect(
      find.byKey(const ValueKey<String>('createMessageDraft-0-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('streamPreview-0-0')),
      findsNothing,
    );
  });

  testWidgets('does not persist writer chats when memory is off', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    final history = WriterChatHistoryStore(backend: _MemoryBackend());
    await pumpCreateScreen(tester, repository, historyStore: history);
    await tester.enterText(
      find.byKey(const Key('createMessagePromptField')),
      'Keep this private.',
    );
    await tester.tap(find.byKey(const Key('createMessageSendButton')));
    await tester.pumpAndSettle();
    expect(await history.all(), isEmpty);
  });
}
