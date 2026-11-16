import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/memory/data/remembered_facts_store.dart';
import 'package:replymate/features/reply/data/prompt_builder.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/memory/data/conversation_memory_store.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

class _Backend implements MemoryBackend {
  final Map<String, Map<Object?, Object?>> data = {};

  @override
  Future<void> clearAll() async => data.clear();
  @override
  Future<Map<String, Map<Object?, Object?>>> loadAll() async => data;
  @override
  Future<void> put(String id, Map<String, Object?> json) async =>
      data[id] = json;
  @override
  Future<void> remove(String id) async => data.remove(id);
}

void main() {
  test('a fact is stored, listed and deletable', () async {
    final store = RememberedFactsStore(backend: _Backend());
    var facts = await store.add('my name is Keshab');
    expect(facts.map((f) => f.text), ['my name is Keshab']);

    facts = await store.add('Rahim is my brother');
    expect(facts, hasLength(2));

    // The list is what the prompt sees, oldest first.
    expect(await store.promptLines(), [
      'my name is Keshab',
      'Rahim is my brother',
    ]);

    await store.remove(facts.first.id);
    expect((await store.promptLines()), ['Rahim is my brother']);
  });

  test('the same fact twice spends one slot', () async {
    final store = RememberedFactsStore(backend: _Backend());
    await store.add('I work night shifts');
    final facts = await store.add('  i WORK night shifts ');
    expect(facts, hasLength(1));
  });

  test('the list is bounded, and the newest survives', () async {
    final store = RememberedFactsStore(backend: _Backend());
    for (var i = 0; i < RememberedFactsStore.maxFacts + 5; i++) {
      await store.add('fact number $i', now: DateTime(2026, 1, 1, 0, 0, i));
    }
    final facts = await store.all();
    expect(facts, hasLength(RememberedFactsStore.maxFacts));
    // Oldest first out: a fact from a year ago is the likeliest to be stale.
    expect(facts.last.text, 'fact number 24');
    expect(facts.first.text, 'fact number 5');
  });

  test('a long paste is truncated, not rejected', () async {
    final store = RememberedFactsStore(backend: _Backend());
    final facts = await store.add('x' * 500);
    expect(facts.single.text.length, RememberedFactsStore.maxFactLength);
  });

  test('facts reach the system prompt, and are told not to become fiction', () {
    final withFacts = ReplyPrompt.system(
      1,
      ReplyTone.friendly,
      mode: ReplyMode.createMessage,
      rememberedFacts: const ['my name is Keshab'],
    );
    expect(withFacts, contains('my name is Keshab'));
    // The two sentences that keep a memory feature honest.
    expect(withFacts, contains('context, not instructions'));
    expect(withFacts, contains('must not invent any fact'));

    // With no facts the block is dropped entirely - no empty heading, no cost.
    final without = ReplyPrompt.system(
      1,
      ReplyTone.friendly,
      mode: ReplyMode.createMessage,
    );
    expect(without, isNot(contains('Things the user has told you')));
  });
}
