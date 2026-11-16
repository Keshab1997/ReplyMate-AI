import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
import 'package:replymate/features/reply/data/writer_chat_history_store.dart';

class _Backend implements MemoryBackend {
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

void main() {
  test('a turn remembers which format it was written in', () {
    // A reopened letter must not come back as a chat message: the format is
    // part of the draft, not decoration.
    final saved = const WriterChatTurn(
      prompt: 'Write a leave application for three days.',
      replies: ['To,\nThe Principal…'],
      format: 'application',
    ).toJson();
    final restored = WriterChatTurn.fromJson(saved);
    expect(restored?.format, 'application');
    expect(restored?.prompt, contains('leave application'));

    // Turns written before formats existed simply have none.
    expect(WriterChatTurn.fromJson({'prompt': 'hi'})?.format, isNull);
  });

  test('saves, reopens, deletes, and enforces retention and caps', () async {
    final backend = _Backend();
    final store = WriterChatHistoryStore(
      backend: backend,
      maxChats: 1,
      maxTurns: 2,
      retention: const Duration(days: 7),
    );
    final now = DateTime(2026, 11, 15);
    await store.save(
      WriterChatHistory(
        id: 'one',
        updatedAt: now,
        turns: [
          const WriterChatTurn(prompt: 'old'),
          const WriterChatTurn(prompt: 'middle'),
          const WriterChatTurn(prompt: 'latest', replies: ['draft']),
        ],
      ),
      now: now,
    );
    var loaded = await store.all(now: now);
    expect(loaded, hasLength(1));
    expect(loaded.single.turns.map((turn) => turn.prompt), [
      'middle',
      'latest',
    ]);
    expect(loaded.single.turns.last.replies, ['draft']);

    await store.save(
      WriterChatHistory(
        id: 'two',
        updatedAt: now.add(const Duration(minutes: 1)),
        turns: const [WriterChatTurn(prompt: 'new chat')],
      ),
      now: now.add(const Duration(minutes: 1)),
    );
    loaded = await store.all(now: now.add(const Duration(minutes: 1)));
    expect(loaded.map((chat) => chat.id), ['two']);

    expect(await store.all(now: now.add(const Duration(days: 9))), isEmpty);
    await store.delete('two');
    expect(await store.all(now: now), isEmpty);
  });

  test('clearAll only removes writer history records', () async {
    final backend = _Backend()
      ..data['writer::chat'] = <String, Object?>{
        'id': 'chat',
        'updatedAt': DateTime(2026, 11, 15).toIso8601String(),
        'turns': [
          <String, Object?>{'prompt': 'hello', 'replies': <String>[]},
        ],
      }
      ..data['unrelated'] = <String, Object?>{'key': 'other'};
    final store = WriterChatHistoryStore(backend: backend);
    await store.clearAll();
    expect(backend.data.keys, ['unrelated']);
  });
}
