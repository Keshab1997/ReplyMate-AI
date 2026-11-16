import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/features/reply/presentation/create_message_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _RecordingCreateRepository repository,
  ) async {
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
}
