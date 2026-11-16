import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../memory/data/conversation_memory_store.dart';

/// A standalone writing chat. It is deliberately stored apart from contact
/// memory, but shares its opt-in switch and its local-only, bounded lifetime.
class WriterChatTurn {
  const WriterChatTurn({
    required this.prompt,
    this.replies = const <String>[],
    this.format,
    this.language,
    this.tone,
    this.length,
  });

  final String prompt;
  final List<String> replies;

  /// The writing format this turn was produced in, as [WritingFormat.id].
  ///
  /// Null for turns saved before formats existed, and for chat messages written
  /// by builds that had only one format. A reopened letter must not be
  /// regenerated as a chat message, so this rides along with the text.
  final String? format;

  /// The reply style this turn was actually written with, as the enum codes
  /// ([ReplyLanguage.code], [ReplyTone.name], [ReplyLength.name]).
  ///
  /// The style belongs to the conversation, not to the app: two chats can be a
  /// formal email in English and a warm Bengali message, and reopening the
  /// second with the first one's tone is the same bug as regenerating a letter
  /// as a chat message. Null for turns saved before the style was recorded.
  final String? language;
  final String? tone;
  final String? length;

  Map<String, Object?> toJson() => <String, Object?>{
    'prompt': prompt,
    'replies': replies,
    if (format != null) 'format': format,
    if (language != null) 'language': language,
    if (tone != null) 'tone': tone,
    if (length != null) 'length': length,
  };

  static WriterChatTurn? fromJson(Object? raw) {
    if (raw is! Map || raw['prompt'] is! String) return null;
    final replies = raw['replies'];
    final format = raw['format'];
    final language = raw['language'];
    final tone = raw['tone'];
    final length = raw['length'];
    return WriterChatTurn(
      prompt: raw['prompt'] as String,
      replies: replies is List
          ? replies.whereType<String>().toList(growable: false)
          : const <String>[],
      format: format is String ? format : null,
      language: language is String ? language : null,
      tone: tone is String ? tone : null,
      length: length is String ? length : null,
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

  /// The newest draft in the chat, one line, for the history list.
  ///
  /// Not the title: two chats can start with the same "Write a birthday
  /// message" and go somewhere completely different, and the thing the user
  /// remembers is what the app wrote, not what they asked for.
  String get preview {
    for (final turn in turns.reversed) {
      for (final reply in turn.replies) {
        final line = reply.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (line.isNotEmpty) return line;
      }
    }
    return '';
  }

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
