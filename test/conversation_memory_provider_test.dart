import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
import 'package:replymate/features/app_selection/providers/selected_apps_provider.dart';
import 'package:replymate/features/memory/providers/conversation_memory_provider.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wiring, not the rules: the switch, the allowlist and the store pulled
/// together the way the app pulls them. Every rule underneath already has its
/// own test; what was never proven is that the thing that calls them actually
/// refuses to write when it should.
class _FakeBackend implements MemoryBackend {
  final Map<String, Map<Object?, Object?>> records = {};
  int clears = 0;
  bool failing = false;

  @override
  Future<Map<String, Map<Object?, Object?>>> loadAll() async {
    if (failing) throw StateError('unavailable');
    return Map<String, Map<Object?, Object?>>.from(records);
  }

  @override
  Future<void> put(String id, Map<String, Object?> json) async {
    if (failing) throw StateError('unavailable');
    records[id] = Map<Object?, Object?>.from(json);
  }

  @override
  Future<void> remove(String id) async {
    records.remove(id);
  }

  @override
  Future<void> clearAll() async {
    clears++;
    records.clear();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackend backend;
  late ProviderContainer container;

  CapturedNotification capture({
    String packageName = 'com.whatsapp',
    String? text = 'kal dekha hobe?',
    String? title = 'Rahim',
    List<String> priorMessages = const <String>[],
    List<String> priorAuthors = const <String>[],
  }) => CapturedNotification(
    packageName: packageName,
    key: 'k',
    title: title,
    text: text,
    priorMessages: priorMessages,
    priorAuthors: priorAuthors,
    isTruncated: false,
    isGrouped: false,
    isGroupSummary: false,
    mayBeRedacted: false,
    hasReplyAction: true,
    postedAtMillis: 0,
  );

  Future<void> build({
    bool memoryOn = false,
    List<String> allowlist = const ['com.whatsapp'],
  }) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefSelectedApps: allowlist,
      ConversationMemorySwitch.prefsKey: memoryOn,
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(AppConstants.channelName),
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        _ => null,
      },
    );
    backend = _FakeBackend();
    container = ProviderContainer(
      overrides: [
        conversationMemoryStoreProvider.overrideWithValue(
          ConversationMemoryStore(backend: backend),
        ),
      ],
    );
    // Let the two async switches (allowlist, memory) finish loading.
    container.read(selectedAppsProvider);
    container.read(conversationMemoryEnabledProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() {
    container.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(AppConstants.channelName),
      null,
    );
  });

  test('with the switch off, generating writes nothing at all', () async {
    await build(memoryOn: false);

    final memory = await container
        .read(conversationMemoryControllerProvider)
        .rememberCapture(capture());

    expect(memory, isNull);
    // The promise that matters most: off means nothing on disk.
    expect(backend.records, isEmpty);
  });

  test('with the switch on and the app allowed, the message is kept', () async {
    await build(memoryOn: true);

    await container
        .read(conversationMemoryControllerProvider)
        .rememberCapture(capture());

    expect(backend.records.keys, ['com.whatsapp::Rahim']);
    final stored = await container
        .read(conversationMemoryControllerProvider)
        .windowFor(capture());
    expect(stored!.contextLines(), ['them: kal dekha hobe?']);
  });

  test('an app outside the allowlist is never written', () async {
    await build(memoryOn: true, allowlist: ['org.telegram.messenger']);

    await container
        .read(conversationMemoryControllerProvider)
        .rememberCapture(capture(packageName: 'com.whatsapp'));

    expect(backend.records, isEmpty);
  });

  test('a capture with no sender name is not filed anywhere', () async {
    await build(memoryOn: true);

    await container
        .read(conversationMemoryControllerProvider)
        .rememberCapture(capture(title: null));

    // A nameless bucket would mix every anonymous notification into one chat.
    expect(backend.records, isEmpty);
  });

  test(
    'an accepted reply is stored as the user, and feeds the voice',
    () async {
      await build(memoryOn: true);
      final controller = container.read(conversationMemoryControllerProvider);

      await controller.rememberCapture(capture());
      await controller.rememberAcceptedReply(
        capture: capture(),
        text: 'haa aschi, ektu deri hobe',
      );

      final window = await controller.windowFor(capture());
      expect(window!.styleExamples(), ['haa aschi, ektu deri hobe']);
      expect(window.ownLineCount, 1);
    },
  );

  test('a screen-read capture stores both sides of the thread', () async {
    await build(memoryOn: true);
    final controller = container.read(conversationMemoryControllerProvider);

    await controller.rememberCapture(
      capture(
        text: 'tahole kal dekha hobe',
        priorMessages: ['kal dekha hobe?', 'haan ashchi'],
        priorAuthors: ['them', 'me'],
      ),
    );

    final window = await controller.windowFor(
      capture(text: 'tahole kal dekha hobe'),
    );
    expect(window!.contextLines(), [
      'them: kal dekha hobe?',
      'me: haan ashchi',
      'them: tahole kal dekha hobe',
    ]);
  });

  test('turning the switch off deletes what was stored', () async {
    await build(memoryOn: true);
    final controller = container.read(conversationMemoryControllerProvider);
    await controller.rememberCapture(capture());
    expect(backend.records, isNotEmpty);

    await container
        .read(conversationMemoryEnabledProvider.notifier)
        .setEnabled(false);

    expect(backend.records, isEmpty);
    expect(backend.clears, 1);
    // And it stays off for the next generation.
    expect(await controller.rememberCapture(capture()), isNull);
    expect(backend.records, isEmpty);
  });

  test(
    'an unusable store still drafts from what was said, it just forgets',
    () async {
      await build(memoryOn: true);
      backend.failing = true;
      final controller = container.read(conversationMemoryControllerProvider);

      final memory = await controller.rememberCapture(capture());

      // The window comes back with this message in it, so the *current* request
      // still gets its context - and nothing reaches the store, so the next one
      // starts empty. Memory degrades; generation never does.
      expect(memory, isNotNull);
      expect(memory!.contextLines(), ['them: kal dekha hobe?']);
      expect((await controller.windowFor(capture()))!.isEmpty, isTrue);
    },
  );
}
