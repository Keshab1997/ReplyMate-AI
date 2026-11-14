import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/core/platform/notifications_bridge.dart';
import 'package:replymate/features/notifications/providers/notification_providers.dart';
import 'package:replymate/features/reply/presentation/reply_composer_screen.dart';
import 'package:replymate/features/settings/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingReplyRepository implements ReplyRepository {
  _RecordingReplyRepository();

  ReplyRequest? request;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    this.request = request;
    return const ReplyFailure('Recorded test request.');
  }
}

// A repository that succeeds, so the inline-drafts path can be asserted.
// Public on purpose: tool/preflight.py reports a private test-only class as
// unused even when a test uses it, and a false red blocks the push.
class SuccessReplyRepository implements ReplyRepository {
  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async => const ReplySuccess(<String>['দেখা হবে না, পরে জানাই।']);
}

const MethodChannel _bridgeChannel = MethodChannel(AppConstants.channelName);

class _ControlledNotificationsBridge extends NotificationsBridge {
  _ControlledNotificationsBridge() : super(channel: _bridgeChannel);

  final StreamController<Map<String, Object?>> _controller =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  int clearRequests = 0;
  int consumeRequests = 0;

  @override
  Stream<Map<String, Object?>> get events => _controller.stream;

  @override
  void startListening() {}

  @override
  Future<LaunchContextMap?> consumeLaunchContext() async {
    consumeRequests++;
    return null;
  }

  @override
  Future<void> clearRetainedContext() async {
    clearRequests++;
  }

  void emit(Map<String, Object?> event) => _controller.add(event);

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}

/// Opens the style sheet from the pinned bar and taps [option]. The composer no
/// longer shows the four chip rows inline - that is the point of the redesign,
/// so every test that changes style goes through the same door a user does.
Future<void> chooseStyle(WidgetTester tester, String option) async {
  await tester.tap(find.text('Change'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridgeChannel,
      (call) async => switch (call.method) {
        'consumeLaunchContext' => null,
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridgeChannel,
      null,
    );
  });

  testWidgets('an empty session explains itself instead of a blank composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _RecordingReplyRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [replyRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No captured notification, no PROCESS_TEXT/SEND text: the composer says
    // why the box is empty.
    expect(find.textContaining('No message was captured'), findsOneWidget);

    // Generate stays tappable on purpose: validation, not a dead button,
    // explains the missing message.
    await tester.ensureVisible(find.text('Generate suggestions'));
    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();

    expect(repository.request, isNull);
    expect(
      find.text('Add a message or paste the text you want to reply to.'),
      findsOneWidget,
    );
  });

  testWidgets('selected suggestion count is sent with the request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _RecordingReplyRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [replyRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Can we meet tomorrow?');
    await chooseStyle(tester, '2');
    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();

    expect(repository.request?.count, 2);
    // The failure is reported in the conversation now, not on a pushed screen.
    expect(find.text('Recorded test request.'), findsOneWidget);
  });

  testWidgets('drafts land in the conversation, not on a pushed screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(SuccessReplyRepository()),
        ],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'কাল দেখা হবে না');
    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();

    // Same route: the draft is on the composer, under the message it answers.
    expect(find.text('দেখা হবে না, পরে জানাই।'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    // And the bar offers a second attempt instead of a first one.
    expect(find.text('Generate again'), findsOneWidget);
  });

  testWidgets('closing the composer clears transient notification context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final bridge = _ControlledNotificationsBridge();
    final container = ProviderContainer(
      overrides: [notificationsBridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(() {
      container.dispose();
      bridge.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReplyComposerScreen(),
                    ),
                  ),
                  child: const Text('Open composer'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();

    bridge.emit({
      'type': 'notification_captured',
      'notification': <String, Object?>{
        'packageName': 'com.whatsapp',
        'key': 'sbn-1',
        'title': 'Asha',
        'text': 'Can we meet tomorrow?',
        'isTruncated': false,
        'isGrouped': false,
        'isGroupSummary': false,
        'mayBeRedacted': false,
        'hasReplyAction': true,
        'replyActionLabel': 'Reply',
        'postedAtMillis': 1,
      },
    });
    await tester.pumpAndSettle();
    expect(container.read(capturedNotificationsProvider), hasLength(1));
    expect(bridge.consumeRequests, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(container.read(capturedNotificationsProvider), isEmpty);
    expect(bridge.clearRequests, 1);

    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();
    expect(bridge.consumeRequests, 2);
    expect(container.read(capturedNotificationsProvider), isEmpty);
  });

  test(
    'clear local preferences also clears transient message context',
    () async {
      final bridge = _ControlledNotificationsBridge();
      final container = ProviderContainer(
        overrides: [notificationsBridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(() {
        container.dispose();
        bridge.dispose();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefDefaultLanguage, 'bn');
      await prefs.setStringList(AppConstants.prefSelectedApps, [
        'com.whatsapp',
      ]);

      container.read(capturedNotificationsProvider.notifier);
      bridge.emit({
        'type': 'notification_captured',
        'notification': <String, Object?>{
          'packageName': 'com.whatsapp',
          'key': 'sbn-2',
          'title': 'Asha',
          'text': 'Private message',
          'isTruncated': false,
          'isGrouped': false,
          'isGroupSummary': false,
          'mayBeRedacted': false,
          'hasReplyAction': false,
          'replyActionLabel': null,
          'postedAtMillis': 2,
        },
      });
      expect(container.read(capturedNotificationsProvider), hasLength(1));

      await container.read(preferencesProvider.notifier).clearAll();

      expect(container.read(capturedNotificationsProvider), isEmpty);
      expect(bridge.clearRequests, 1);
      expect(prefs.getString(AppConstants.prefDefaultLanguage), isNull);
      expect(prefs.getStringList(AppConstants.prefSelectedApps), isNull);
    },
  );

  testWidgets('the composer speaks the interface language, not English', (
    tester,
  ) async {
    // The point of the sweep: a Bengali session must not meet English copy in
    // the screen it uses most. This asserts on the composer's own strings, which
    // used to be literals.
    SharedPreferences.setMockInitialValues({
      AppConstants.prefAppLanguage: 'bn',
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _RecordingReplyRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [replyRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('নতুন জবাব'), findsOneWidget);
    expect(
      find.text(
        'No message was captured. ReplyMate only keeps a message '
        'while the app is running; open ReplyMate after a new message arrives, '
        'or paste the text.',
      ),
      findsNothing,
    );
    expect(find.textContaining('কোনো মেসেজ ধরা পড়েনি'), findsOneWidget);
    expect(find.text('পরামর্শ তৈরি করুন'), findsOneWidget);
  });

  testWidgets('detects Bengali text and offers one-tap offline replies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _RecordingReplyRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [replyRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ধন্যবাদ');
    await tester.pumpAndSettle();

    expect(find.text('Quick replies'), findsOneWidget);
    // The detected language is stated in the pinned bar; the chips live in the
    // sheet, one tap away.
    expect(find.textContaining('Bengali'), findsOneWidget);
    await tester.tap(find.text('স্বাগতম!'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline suggestions'), findsOneWidget);
    expect(repository.request, isNull);
  });

  testWidgets('saved templates appear only when available and open offline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefSavedReplies: ['I will get back to you soon.'],
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(
            _RecordingReplyRepository(),
          ),
        ],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My reply templates (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I will get back to you soon.'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline suggestions'), findsOneWidget);
    expect(find.text('I will get back to you soon.'), findsOneWidget);
  });

  testWidgets('a hindi session renders hindi, including the style labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefAppLanguage: 'hi',
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyRepositoryProvider.overrideWithValue(
            _RecordingReplyRepository(),
          ),
        ],
        child: const MaterialApp(home: ReplyComposerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('नया जवाब'), findsOneWidget);
    expect(find.text('सुझाव बनाएँ'), findsOneWidget);
    // The style labels moved into the sheet - so the sheet has to be Hindi too.
    final changeHindi = const HindiStrings().change;
    expect(find.text(changeHindi), findsOneWidget);
    await tester.tap(find.text(changeHindi));
    await tester.pumpAndSettle();
    expect(find.text('भाषा'), findsOneWidget);
    expect(find.text(const HindiStrings().toneLabel), findsOneWidget);
    expect(find.text('हो गया'), findsOneWidget);
  });
}
