import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/features/reply/domain/writing_format.dart';
import 'package:replymate/features/reply/presentation/create_message_screen.dart';
import 'package:replymate/features/reply/data/writer_chat_history_store.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
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
  int calls = 0;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    calls++;
    this.request = request;
    requests.add(request);
    return const ReplySuccess(['তুমি আমার দিনের সবচেয়ে সুন্দর ভাবনা।']);
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
    _RecordingCreateRepository repository, {
    bool memoryEnabled = false,
    WriterChatHistoryStore? historyStore,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (memoryEnabled) 'conversation_memory_enabled': true,
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(repository),
          if (historyStore != null)
            writerChatHistoryStoreProvider.overrideWithValue(historyStore),
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

    // A chat format's inspiration is romantic lines; an application's is
    // applications. Showing the wrong one is how a feature looks broken.
    expect(
      find.text(const EnglishStrings().exampleRomanticQuote),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('openWritingFormatMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('writingFormat-email')));
    await tester.pumpAndSettle();

    expect(
      find.text(const EnglishStrings().exampleRomanticQuote),
      findsNothing,
    );
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
    expect(repository.request?.message, contains('romantic quote'));
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
