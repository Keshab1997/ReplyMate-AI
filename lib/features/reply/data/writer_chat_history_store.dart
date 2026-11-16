import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../memory/data/conversation_memory_store.dart';

/// A standalone writing chat. It is deliberately stored apart from contact
/// memory, but shares its opt-in switch and its local-only, bounded lifetime.
class WriterChatTurn {
  const WriterChatTurn({required this.prompt, this.replies = const <String>[]});

  final String prompt;
  final List<String> replies;

  Map<String, Object?> toJson() => <String, Object?>{
    'prompt': prompt,
    'replies': replies,
  };

  static WriterChatTurn? fromJson(Object? raw) {
    if (raw is! Map || raw['prompt'] is! String) return null;
    final replies = raw['replies'];
    return WriterChatTurn(
      prompt: raw['prompt'] as String,
      replies: replies is List
          ? replies.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }
}

class WriterChatHistory {
  const WriterChatHistory({
    required this.id,
    required this.updatedAt,
    required this.turns,
  });

  final String id;
  final DateTime updatedAt;
  final List<WriterChatTurn> turns;

  String get title => turns.isEmpty ? '' : turns.first.prompt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'updatedAt': updatedAt.toIso8601String(),
    'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
  };

  static WriterChatHistory? fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    final updatedAt = json['updatedAt'];
    final rawTurns = json['turns'];
    if (id is! String || updatedAt is! String || rawTurns is! List) {
      return null;
    }
    final parsedAt = DateTime.tryParse(updatedAt);
    if (parsedAt == null) return null;
    final turns = rawTurns
        .map(WriterChatTurn.fromJson)
        .whereType<WriterChatTurn>()
        .toList(growable: false);
    if (turns.isEmpty) return null;
    return WriterChatHistory(id: id, updatedAt: parsedAt, turns: turns);
  }
}

/// Bounded, device-local history. The same consent switch governs this store;
/// standalone chats have no contact key, so they use their own 50-chat cap and
/// the same 7-day retention / 40-turn ceiling as conversation memory.
final writerChatHistoryStoreProvider = Provider<WriterChatHistoryStore>(
  (ref) => WriterChatHistoryStore(),
);

class WriterChatHistoryStore {
  WriterChatHistoryStore({
    MemoryBackend? backend,
    this.retention = const Duration(days: 7),
    this.maxChats = 50,
    this.maxTurns = 40,
  }) : _backend = backend ?? HiveMemoryBackend(boxName: boxName);

  static const String boxName = 'writer_chat_history_v1';
  static const String _prefix = 'writer::';
  final MemoryBackend _backend;
  final Duration retention;
  final int maxChats;
  final int maxTurns;

  Future<List<WriterChatHistory>> all({DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      final records = await _backend.loadAll();
      final histories = <WriterChatHistory>[];
      for (final entry in records.entries) {
        if (!entry.key.startsWith(_prefix)) continue;
        final history = WriterChatHistory.fromJson(entry.value);
        if (history == null || at.difference(history.updatedAt) > retention) {
          await _backend.remove(entry.key);
          continue;
        }
        histories.add(history);
      }
      histories.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return histories;
    } catch (_) {
      return const <WriterChatHistory>[];
    }
  }

  Future<void> save(WriterChatHistory history, {DateTime? now}) async {
    try {
      final at = now ?? DateTime.now();
      final boundedTurns = history.turns.length <= maxTurns
          ? history.turns
          : history.turns.sublist(history.turns.length - maxTurns);
      if (boundedTurns.isEmpty) return;
      final bounded = WriterChatHistory(
        id: history.id,
        updatedAt: at,
        turns: List<WriterChatTurn>.unmodifiable(boundedTurns),
      );
      final key = '$_prefix${history.id}';
      await _backend.put(key, bounded.toJson());
      final saved = await all(now: at);
      for (final old in saved.skip(maxChats)) {
        await _backend.remove('$_prefix${old.id}');
      }
    } catch (_) {
      // History is optional and must never interrupt writing.
    }
  }

  Future<void> delete(String id) async {
    try {
      await _backend.remove('$_prefix$id');
    } catch (_) {}
  }

  Future<void> clearAll() async {
    try {
      final records = await _backend.loadAll();
      for (final key in records.keys.where((key) => key.startsWith(_prefix))) {
        await _backend.remove(key);
      }
    } catch (_) {}
  }
}
