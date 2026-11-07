import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/core/platform/notifications_bridge.dart';
import 'package:replymate/features/notifications/providers/notification_providers.dart';
import 'package:replymate/features/reply/presentation/reply_composer_screen.dart';
import 'package:replymate/features/settings/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingReplyRepository implements ReplyRepository {
  _RecordingReplyRepository();

  ReplyRequest? request;

  @override
  Future<ReplyResult> generate(ReplyRequest request) async {
    this.request = request;
    return const ReplyFailure('Recorded test request.');
  }
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
    // why the box is empty (docs/OVERLAY_TASKS.md Batch 0).
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
    await tester.ensureVisible(find.text('2'));
    await tester.tap(find.text('2'));
    await tester.ensureVisible(find.text('Generate suggestions'));
    await tester.tap(find.text('Generate suggestions'));
    await tester.pumpAndSettle();

    expect(repository.request?.count, 2);
    expect(find.text('Recorded test request.'), findsOneWidget);
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
}
