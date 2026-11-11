@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';

/// The one property of the real backend that a fake cannot prove: after another
/// isolate writes to the box, this one must see it.
///
/// This is not a hypothetical. The reply panel is a second Flutter engine, so a
/// second Dart isolate with its own Hive instance. A box left open in the main
/// app served its stale in-memory copy and the Settings list stayed empty while
/// the save had worked - "memory does not save" on a device, with nothing wrong
/// with the save.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('replymate_memory_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a write from a real second isolate is visible to this backend', () async {
    const boxName = 'memory_isolation_test';
    final backend = HiveMemoryBackend(boxName: boxName);
    final path = dir.path;

    await backend.put('com.whatsapp::Rahim', {
      'key': 'com.whatsapp::Rahim',
      'lines': [
        {
          'text': 'from the main isolate',
          'author': 'them',
          'at': '2026-11-11T12:00:00Z',
        },
      ],
    });

    // A real second isolate with its own Hive - which is what the reply panel
    // is. Within one isolate `openBox` hands back the same instance, so only a
    // separate isolate can prove that a cached box goes stale.
    await Isolate.run(() async {
      Hive.init(path);
      final box = await Hive.openBox<String>(boxName);
      await box.put(
        'com.whatsapp::Karim',
        '{"key":"com.whatsapp::Karim","lines":['
            '{"text":"from the other isolate","author":"them",'
            '"at":"2026-11-11T12:01:00Z"}]}',
      );
      await box.flush();
      await box.close();
    });

    final all = await backend.loadAll();

    expect(
      all.keys,
      containsAll(<String>['com.whatsapp::Rahim', 'com.whatsapp::Karim']),
      reason: 'the backend must read the disk, not a cache it opened earlier',
    );
  });

  test('the backend survives a box another client closed', () async {
    // A close by someone else must not make every later operation fail.
    const boxName = 'memory_close_test';
    final backend = HiveMemoryBackend(boxName: boxName);

    final other = await Hive.openBox<String>(boxName);
    await other.put('a', '{"key":"a","lines":[]}');
    await other.flush();
    await other.close();

    await backend.put('b', {
      'key': 'b',
      'lines': [
        {
          'text': 'still writable',
          'author': 'me',
          'at': '2026-11-11T12:00:00Z',
        },
      ],
    });

    expect((await backend.loadAll()).keys, containsAll(<String>['a', 'b']));
  });

  test('a store over the real backend round-trips a window', () async {
    const boxName = 'memory_roundtrip_test';
    final backend = HiveMemoryBackend(boxName: boxName);
    final store = ConversationMemoryStore(backend: backend);
    final key = ConversationKey.tryOf(
      packageName: 'com.whatsapp',
      contactName: 'Riya',
    )!;
    final now = DateTime.utc(2026, 11, 11, 12);

    await store.save(
      ConversationMemory.fromStored(
        key: key,
        now: now,
        lines: [
          MemoryLine(
            text: 'kal dekha hobe?',
            author: MemoryAuthor.them,
            at: now,
          ),
        ],
      ),
      now: now,
    );

    final window = await store.read(key, now: now);
    expect(window.contextLines(), ['them: kal dekha hobe?']);
    expect((await store.contacts(now: now)).map((k) => k.contactName), [
      'Riya',
    ]);

    await store.forgetAll();
    expect((await store.read(key, now: now)).isEmpty, isTrue);
  });
}
