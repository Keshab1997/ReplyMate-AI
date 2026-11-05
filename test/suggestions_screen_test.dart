import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/features/reply/presentation/suggestions_screen.dart';

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

Widget app(Widget screen) => ProviderScope(child: MaterialApp(home: screen));

/// Outbound calls on the bridge channel hang in widget tests when the app has
/// registered an inbound handler on the same channel but no mock exists.
/// Mock the honest no-native-layer answer: sendQuickReply fails (false).
const MethodChannel bridgeChannel = MethodChannel(
  'com.keshabstudios.replymate/notifications',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;

  setUp(() {
    // Capture Clipboard.setData instead of touching a real clipboard.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      (call) async => switch (call.method) {
        'sendQuickReply' => false,
        'isListenerEnabled' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      null,
    );
  });

  testWidgets('quick reply is hidden when no reply action exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SuggestionsScreen(
          replies: const ['Sure!', 'Yes.'],
          request: request,
          context: contextWith(hasReplyAction: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quick reply'), findsNothing);
    expect(
      find.textContaining('Quick reply works only in apps that support it'),
      findsOneWidget,
    );
  });

  testWidgets(
    'quick reply appears only with a valid action, and its failure falls back honestly',
    (tester) async {
      await tester.pumpWidget(
        app(
          SuggestionsScreen(
            replies: const ['Sure!'],
            request: request,
            context: contextWith(hasReplyAction: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quick reply'), findsOneWidget);

      // No native layer in tests: sendQuickReply answers false, and the UI must
      // say the action is gone instead of claiming success.
      await tester.tap(find.text('Quick reply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer valid'), findsOneWidget);
    },
  );

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
