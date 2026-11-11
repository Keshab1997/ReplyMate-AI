import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/conversation_memory.dart';

/// The raw storage a [ConversationMemoryStore] sits on.
///
/// An interface, for the same reason `KeySource` is one: the store's rules -
/// the per-contact cap, eviction when there are too many contacts, "a broken
/// record costs nobody their reply" - are the parts worth testing, and none of
/// them need a real box on a real device to be proven.
abstract interface class MemoryBackend {
  /// Every stored contact, id -> its JSON. Unreadable entries are dropped by
  /// the implementation rather than thrown: the store must always be openable.
  Future<Map<String, Map<Object?, Object?>>> loadAll();

  Future<void> put(String id, Map<String, Object?> json);

  Future<void> remove(String id);

  Future<void> clearAll();
}

/// The real backend: one Hive box under the app's own documents directory.
///
/// Two things here are deliberate and easy to get wrong.
///
/// 1. It initialises Hive itself instead of assuming someone else did. Hive is
///    normally started by `bootstrapFirebase`, which returns early when
///    `google-services.json` is missing - and the guest-mode invariant says the
///    app must work fully without Firebase. A store that silently stopped
///    working in guest mode would be the exact bug that invariant exists to
///    prevent.
/// 2. Every failure is swallowed into "no memory". docs/CONVERSATION_MEMORY.md
///    §9: memory is never allowed to break generation.
class HiveMemoryBackend implements MemoryBackend {
  HiveMemoryBackend({this.boxName = defaultBoxName});

  /// `_v1` because the stored shape is a promise: bump it and old memory is
  /// simply not read, rather than being misread.
  static const String defaultBoxName = 'conversation_memory_v1';

  final String boxName;

  /// Operations run one at a time.
  ///
  /// Not caution: the box is opened and closed by every operation, so two
  /// overlapping calls in this isolate could have one closing the box the other
  /// is still reading. Serialising is cheap here (the store holds at most 50
  /// chats) and removes a whole class of "Box has already been closed" failures
  /// from the path that must never break a reply.
  Future<void> _tail = Future<void>.value();

  /// Runs one operation against the box, then **closes it again**.
  ///
  /// The close is the whole point, and it is not tidiness. The reply panel runs
  /// in its own Flutter engine, which means its own Dart isolate, which means
  /// its own Hive instance holding its own in-memory copy of every box it has
  /// opened. A box kept open in the main app never sees what the panel wrote -
  /// the write is on disk and the main app keeps serving its stale cache - so
  /// "remembered in the bubble, invisible in Settings" is exactly what happens.
  /// Reopening per operation makes the disk the single source of truth, at the
  /// cost of a tiny file read for a store capped at 50 chats.
  Future<T> _withBox<T>(
    T fallback,
    Future<T> Function(Box<String> box) action,
  ) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    Box<String>? box;
    try {
      await previous;
      box = await _open();
      return await action(box);
    } catch (error) {
      // Memory is never allowed to break generation (docs/CONVERSATION_MEMORY.md
      // §9), and one bad open must not poison every later attempt.
      debugPrint('ReplyMate: conversation memory unavailable ($error)');
      return fallback;
    } finally {
      try {
        if (box != null && box.isOpen) await box.close();
      } catch (_) {
        // A failed close costs nothing: the next operation reopens.
      }
      // Released whatever happened, so one failure cannot stall the queue.
      released.complete();
    }
  }

  Future<Box<String>> _open() async {
    if (!Hive.isBoxOpen(boxName)) {
      try {
        // Safe to call again: with Firebase configured this is a no-op on the
        // path it already set, and in guest mode it is the only init. Each
        // isolate needs it, because each isolate has its own Hive.
        await Hive.initFlutter();
      } catch (_) {
        // Already initialised by bootstrap; keep going.
      }
    }
    return Hive.openBox<String>(boxName);
  }

  @override
  Future<Map<String, Map<Object?, Object?>>> loadAll() =>
      _withBox(const <String, Map<Object?, Object?>>{}, (box) async {
        final result = <String, Map<Object?, Object?>>{};
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              result['$key'] = Map<Object?, Object?>.from(decoded);
            }
          } catch (_) {
            // A corrupt record is one lost contact, never a lost store.
            continue;
          }
        }
        return result;
      });

  @override
  Future<void> put(String id, Map<String, Object?> json) =>
      _withBox(null, (box) async {
        await box.put(id, jsonEncode(json));
        // Flushed before the box closes, so the other isolate reads what was
        // actually written rather than what was queued.
        await box.flush();
      });

  @override
  Future<void> remove(String id) => _withBox(null, (box) async {
    await box.delete(id);
    await box.flush();
  });

  @override
  Future<void> clearAll() => _withBox(null, (box) async {
    await box.clear();
    await box.flush();
  });
}

/// The store proper: per-contact windows with the cap from
/// docs/CONVERSATION_MEMORY.md §4, over any [MemoryBackend].
///
/// Nothing in here decides *whether* memory is allowed - that is the switch and
/// the recorder's job. This class answers "what do we have" and "keep this".
class ConversationMemoryStore {
  ConversationMemoryStore({
    MemoryBackend? backend,
    this.policy = MemoryPolicy.standard,
  }) : _backend = backend ?? HiveMemoryBackend();

  final MemoryBackend _backend;
  final MemoryPolicy policy;

  /// This contact's window, already capped and expired-out. Never throws and
  /// never returns null: an unreadable store is an empty memory, which is a
  /// state the rest of the app already knows how to be honest about.
  Future<ConversationMemory> read(ConversationKey key, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      final all = await _backend.loadAll();
      final record = all[key.id];
      if (record == null) {
        return ConversationMemory.empty(key: key, policy: policy);
      }
      return ConversationMemory.fromJson(
            record,
            key: key,
            now: at,
            policy: policy,
          ) ??
          ConversationMemory.empty(key: key, policy: policy);
    } catch (_) {
      return ConversationMemory.empty(key: key, policy: policy);
    }
  }

  /// Writes the window back and keeps the number of contacts inside
  /// [MemoryPolicy.maxContacts].
  ///
  /// An empty window deletes instead of storing an empty husk, so "forget this
  /// contact" and "everything in it aged out" end in the same place: nothing on
  /// disk.
  Future<void> save(ConversationMemory memory, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      if (memory.isEmpty) {
        await _backend.remove(memory.key.id);
        return;
      }
      await _backend.put(memory.key.id, memory.toJson());
      await _evictExtraContacts(keep: memory.key.id, now: at);
    } catch (_) {
      // A failed write loses one line of context. It must not surface as a
      // broken reply.
      return;
    }
  }

  Future<void> forget(ConversationKey key) async {
    try {
      await _backend.remove(key.id);
    } catch (_) {
      return;
    }
  }

  /// Turning the switch off calls this: gone, not frozen
  /// (docs/CONVERSATION_MEMORY.md §3, wall 1).
  Future<void> forgetAll() async {
    try {
      await _backend.clearAll();
    } catch (_) {
      return;
    }
  }

  /// The contacts that have memory, newest activity first - what the Settings
  /// list shows and what the user deletes one at a time.
  Future<List<ConversationKey>> contacts({DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      final all = await _backend.loadAll();
      final entries = <(ConversationKey, DateTime)>[];
      for (final record in all.values) {
        final parsed = _parseKey(record);
        if (parsed == null) continue;
        final memory = ConversationMemory.fromJson(
          record,
          key: parsed,
          now: at,
          policy: policy,
        );
        if (memory == null || memory.isEmpty) continue;
        entries.add((parsed, memory.lines.last.at));
      }
      entries.sort((a, b) => b.$2.compareTo(a.$2));
      return <ConversationKey>[for (final entry in entries) entry.$1];
    } catch (_) {
      return const <ConversationKey>[];
    }
  }

  /// Drops the least recently active contacts past the cap. The contact just
  /// written is never a candidate, so a write can always complete.
  Future<void> _evictExtraContacts({
    required String keep,
    required DateTime now,
  }) async {
    final all = await _backend.loadAll();
    if (all.length <= policy.maxContacts) return;

    final ranked = <(String, DateTime)>[];
    for (final entry in all.entries) {
      if (entry.key == keep) continue;
      final memory = _parseKey(entry.value);
      final record = memory == null
          ? null
          : ConversationMemory.fromJson(
              entry.value,
              key: memory,
              now: now,
              policy: policy,
            );
      ranked.add((
        entry.key,
        record == null || record.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : record.lines.last.at,
      ));
    }
    ranked.sort((a, b) => a.$2.compareTo(b.$2));

    final excess = all.length - policy.maxContacts;
    for (var i = 0; i < excess && i < ranked.length; i++) {
      await _backend.remove(ranked[i].$1);
    }
  }

  static ConversationKey? _parseKey(Map<Object?, Object?> record) {
    final id = record['key'];
    if (id is! String) return null;
    final split = id.indexOf('::');
    if (split <= 0) return null;
    return ConversationKey.tryOf(
      packageName: id.substring(0, split),
      contactName: id.substring(split + 2),
    );
  }
}
