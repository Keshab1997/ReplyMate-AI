import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';

/// A backend in a map. The store's rules are about caps and eviction, and none
/// of them need Hive, a device, or a platform channel to be true.
class _FakeBackend implements MemoryBackend {
  final Map<String, Map<Object?, Object?>> records = {};

  int writes = 0;
  int removals = 0;
  int clears = 0;
  bool failing = false;

  @override
  Future<Map<String, Map<Object?, Object?>>> loadAll() async {
    if (failing) throw StateError('store unavailable');
    return Map<String, Map<Object?, Object?>>.from(records);
  }

  @override
  Future<void> put(String id, Map<String, Object?> json) async {
    if (failing) throw StateError('store unavailable');
    writes++;
    records[id] = Map<Object?, Object?>.from(json);
  }

  @override
  Future<void> remove(String id) async {
    removals++;
    records.remove(id);
  }

  @override
  Future<void> clearAll() async {
    clears++;
    records.clear();
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);

  const tight = MemoryPolicy(maxLinesPerContact: 3, maxContacts: 2);

  ConversationKey keyOf(String contact) =>
      ConversationKey.tryOf(packageName: 'com.whatsapp', contactName: contact)!;

  MemoryLine them(String text, {int minutesAgo = 0}) => MemoryLine(
    text: text,
    author: MemoryAuthor.them,
    at: now.subtract(Duration(minutes: minutesAgo)),
  );

  late _FakeBackend backend;
  late ConversationMemoryStore store;

  setUp(() {
    backend = _FakeBackend();
    store = ConversationMemoryStore(backend: backend, policy: tight);
  });

  group('reading', () {
    test('an unknown contact is an empty window, not an error', () async {
      final memory = await store.read(keyOf('Rahim'), now: now);

      expect(memory.isEmpty, isTrue);
      expect(memory.key.contactName, 'Rahim');
    });

    test('a stored window comes back capped and ordered', () async {
      final key = keyOf('Rahim');
      await store.save(
        ConversationMemory.fromStored(
          key: key,
          now: now,
          policy: tight,
          lines: [
            them('one', minutesAgo: 3),
            them('two', minutesAgo: 2),
            them('three', minutesAgo: 1),
            them('four', minutesAgo: 0),
          ],
        ),
        now: now,
      );

      final memory = await store.read(key, now: now);

      expect(memory.lines.map((line) => line.text), ['two', 'three', 'four']);
    });

    test('an unreadable store is an empty window, never a throw', () async {
      // §9: memory is never allowed to break generation. A store that throws
      // here would take the reply down with it.
      backend.failing = true;

      final memory = await store.read(keyOf('Rahim'), now: now);

      expect(memory.isEmpty, isTrue);
    });
  });

  group('writing', () {
    test('saves a window under the contact id', () async {
      final key = keyOf('Rahim');
      await store.save(
        ConversationMemory.fromStored(
          key: key,
          now: now,
          policy: tight,
          lines: [them('hello there', minutesAgo: 0)],
        ),
        now: now,
      );

      expect(backend.records.keys, [key.id]);
    });

    test('an empty window deletes instead of storing a husk', () async {
      final key = keyOf('Rahim');
      await store.save(
        ConversationMemory.fromStored(
          key: key,
          now: now,
          policy: tight,
          lines: [them('hello there', minutesAgo: 0)],
        ),
        now: now,
      );

      await store.save(ConversationMemory.empty(key: key, policy: tight), now: now);

      // "everything aged out" and "the user deleted this contact" end in the
      // same place: nothing on disk.
      expect(backend.records, isEmpty);
    });

    test('a failed write is silent', () async {
      backend.failing = true;

      await expectLater(
        store.save(
          ConversationMemory.fromStored(
            key: keyOf('Rahim'),
            now: now,
            policy: tight,
            lines: [them('hello there', minutesAgo: 0)],
          ),
          now: now,
        ),
        completes,
      );
    });
  });

  group('forgetting', () {
    test('forget drops one contact and leaves the others', () async {
      await store.save(_window('Rahim', now, tight), now: now);
      await store.save(_window('Karim', now, tight), now: now);

      await store.forget(keyOf('Rahim'));

      expect(backend.records.keys, [keyOf('Karim').id]);
    });

    test('forgetAll empties the store, which is what the switch promises', () async {
      await store.save(_window('Rahim', now, tight), now: now);
      await store.save(_window('Karim', now, tight), now: now);

      await store.forgetAll();

      expect(backend.records, isEmpty);
      expect(backend.clears, 1);
      // Gone, not frozen (§3 wall 1): "off" must not mean "still on disk".
    });
  });

  group('the contact cap', () {
    test('evicts the least recently active and keeps the one just written', () async {
      await store.save(
        _window('Old', now, tight, minutesAgo: 120),
        now: now,
      );
      await store.save(
        _window('Older', now, tight, minutesAgo: 240),
        now: now,
      );

      // Third contact pushes past maxContacts: 2.
      await store.save(_window('New', now, tight), now: now);

      expect(backend.records.length, tight.maxContacts);
      expect(backend.records.containsKey(keyOf('New').id), isTrue);
      // 'Older' was the coldest, so it goes.
      expect(backend.records.containsKey(keyOf('Older').id), isFalse);
    });

    test('listing contacts puts the newest activity first', () async {
      await store.save(_window('Quiet', now, tight, minutesAgo: 90), now: now);
      await store.save(_window('Chatty', now, tight, minutesAgo: 1), now: now);

      final contacts = await store.contacts(now: now);

      expect(contacts.map((key) => key.contactName), ['Chatty', 'Quiet']);
    });

    test('expired contacts are not listed', () async {
      await store.save(
        _window('Stale', now, tight, minutesAgo: 60 * 24 * 30),
        now: now,
      );

      expect(await store.contacts(now: now), isEmpty);
    });
  });
}

ConversationMemory _window(
  String contact,
  DateTime now,
  MemoryPolicy policy, {
  int minutesAgo = 0,
}) => ConversationMemory.fromStored(
  key: ConversationKey.tryOf(
    packageName: 'com.whatsapp',
    contactName: contact,
  )!,
  now: now,
  policy: policy,
  lines: [
    MemoryLine(
      text: '$contact said something',
      author: MemoryAuthor.them,
      at: now.subtract(Duration(minutes: minutesAgo)),
    ),
  ],
);
