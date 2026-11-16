import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'conversation_memory_store.dart';

/// One thing the user told the app to remember about themselves or someone
/// else - "my name is Keshab", "Rahim is my brother", "I work night shifts".
class RememberedFact {
  const RememberedFact({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  /// Stable id, also the store key. Microseconds since epoch.
  final String id;

  /// The fact, in the user's own words. Never a model's paraphrase: a memory
  /// the app invented is worse than no memory, because it is unfalsifiable.
  final String text;

  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  static RememberedFact? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['text'] is! String) {
      return null;
    }
    final at = DateTime.tryParse(raw['createdAt'] as String? ?? '');
    if (at == null) return null;
    final text = (raw['text'] as String).trim();
    if (text.isEmpty) return null;
    return RememberedFact(id: raw['id'] as String, text: text, createdAt: at);
  }
}

/// Facts the user asked the app to keep, on this device only.
///
/// Three walls, and each is the point:
///
/// * **The user writes them.** Nothing here is inferred from a message, a tone
///   or a pattern of replies. An inferred profile is a thing the app cannot
///   show you, cannot let you correct, and cannot honestly delete - so it does
///   not exist. What exists is a list you typed and can read back.
/// * **Bounded.** [maxFacts] facts of [maxFactLength] characters each. A note
///   that grows forever becomes a dossier.
/// * **Deleted with the same switch.** The master memory switch deletes this
///   along with the conversations: "off" means off, not "off except the bit I
///   like".
class RememberedFactsStore {
  RememberedFactsStore({MemoryBackend? backend})
    : _backend = backend ?? HiveMemoryBackend(boxName: boxName);

  static const String boxName = 'remembered_facts_v1';
  static const String _prefix = 'fact::';

  /// Enough for who is who, and not enough to become a profile.
  static const int maxFacts = 20;

  /// A "fact" longer than this is a message, and messages have their own
  /// bounded shelf.
  static const int maxFactLength = 160;

  final MemoryBackend _backend;

  Future<List<RememberedFact>> all() async {
    try {
      final records = await _backend.loadAll();
      final facts = <RememberedFact>[];
      for (final entry in records.entries) {
        if (!entry.key.startsWith(_prefix)) continue;
        final fact = RememberedFact.fromJson(entry.value);
        if (fact != null) facts.add(fact);
      }
      facts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return facts;
    } catch (_) {
      return const <RememberedFact>[];
    }
  }

  /// Adds a fact and returns the bounded list.
  ///
  /// A fact already on the list is not stored twice, case-insensitively: the
  /// user repeating themselves should not spend two of twenty slots.
  Future<List<RememberedFact>> add(String text, {DateTime? now}) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return all();
    final bounded = cleaned.length <= maxFactLength
        ? cleaned
        : cleaned.substring(0, maxFactLength);
    try {
      final existing = await all();
      final folded = bounded.toLowerCase();
      if (existing.any((fact) => fact.text.toLowerCase() == folded)) {
        return existing;
      }
      final at = now ?? DateTime.now();
      final fact = RememberedFact(
        id: '${at.microsecondsSinceEpoch}',
        text: bounded,
        createdAt: at,
      );
      await _backend.put('$_prefix${fact.id}', fact.toJson());
      final next = await all();
      // Oldest first out: the newest thing the user said is the most likely to
      // still be true.
      for (final old in next.take(
        (next.length - maxFacts).clamp(0, next.length),
      )) {
        await _backend.remove('$_prefix${old.id}');
      }
      return await all();
    } catch (_) {
      return const <RememberedFact>[];
    }
  }

  Future<List<RememberedFact>> remove(String id) async {
    try {
      await _backend.remove('$_prefix$id');
    } catch (_) {
      // Forgetting is best-effort; the list that comes back is the truth.
    }
    return await all();
  }

  Future<void> clearAll() async {
    try {
      final records = await _backend.loadAll();
      for (final key in records.keys.where((key) => key.startsWith(_prefix))) {
        await _backend.remove(key);
      }
    } catch (_) {}
  }

  /// What the prompt gets: one short line per fact, oldest first.
  Future<List<String>> promptLines() async => [
    for (final fact in await all()) fact.text,
  ];
}

final Provider<RememberedFactsStore> rememberedFactsStoreProvider =
    Provider<RememberedFactsStore>((Ref ref) => RememberedFactsStore());
