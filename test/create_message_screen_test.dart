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
  int calls = 0;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    calls++;
    this.request = request;
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
    await tester.tap(find.text(const EnglishStrings().generateSuggestions));
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

  testWidgets(
    'opening the writer does not generate and empty submit explains',
    (tester) async {
      final repository = _RecordingCreateRepository();
      await pumpCreateScreen(tester, repository);

      expect(repository.calls, 0);
      await tester.tap(find.text(const EnglishStrings().generateSuggestions));
      await tester.pumpAndSettle();

      expect(repository.calls, 0);
      expect(
        find.text(const EnglishStrings().createMessageEmpty),
        findsOneWidget,
      );
    },
  );
}
