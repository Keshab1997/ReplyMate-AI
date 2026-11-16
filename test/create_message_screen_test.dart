import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
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
