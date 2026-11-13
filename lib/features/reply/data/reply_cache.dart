import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../domain/reply_request.dart';

/// A reply set kept from an identical earlier request.
class CachedReplies {
  const CachedReplies(this.replies, this.storedAt);

  final List<String> replies;
  final DateTime storedAt;
}

/// On-device cache for generated replies, keyed on a hash of the request.
///
/// Why it exists: the same message arrives over and over — "ok", "hi", a
/// delivery ping — and every one of those taps was a paid provider call. A hit
/// here costs nothing at all.
///
/// The three rules that keep it honest:
/// - **Content never leaves the device to be cached.** The key is a hash of
///   what the user already chose to send; the reply itself is stored locally,
///   exactly like conversation memory, and deleted when it expires.
/// - **A hit is labelled.** [CachedReplies] carries its timestamp so the UI can
///   say "from cache" and offer a real regenerate. A cached reply presented as
///   fresh would be a lie about what just happened.
/// - **Time-sensitive messages are never served from cache.** "kal asbo?" has
///   a different answer tomorrow, so a message mentioning a day, date or
///   relative time bypasses the cache entirely.
class ReplyCache {
  // ignore: prefer_initializing_formals — the field is private, the parameter
  // is not `this._box`, because a caller passing `box:` reads better than one
  // passing `_box:`.
  ReplyCache({
    this.box,
    this.ttl = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// A cache that stores nothing — the honest default before Hive is open, and
  /// what tests get when they do not care about caching.
  factory ReplyCache.disabled() => ReplyCache(box: null);

  static const String boxName = 'reply_cache';
  static const int _maxEntries = 300;

  /// The box replies are stored in, or null for a cache that stores nothing.
  final Box<dynamic>? box;
  final Duration ttl;
  final DateTime Function() _now;

  /// Opens the package's own box. Separate from the settings box so clearing
  /// the cache can never take a preference with it.
  static Future<Box<dynamic>> openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  /// The cache key for [request]. Every field that changes the answer is in it;
  /// nothing that does not (no timestamps, no session ids) is.
  static String keyFor(ReplyRequest request) {
    final parts = <String>[
      request.trimmedMessage,
      request.language.code,
      request.tone.name,
      request.length.name,
      '${request.count}',
      // Prior context changes the answer, so it is part of the key. Style
      // examples are the user's own voice, which does not change a reply's
      // content enough to justify a cache miss on every new example.
      request.priorMessages.join('\u0001'),
    ];
    return base64Url.encode(utf8.encode(parts.join('\u0002')));
  }

  /// Word boundary used for the romanised markers: "kolkata" contains "kal" and
  /// must not be treated as a time reference.
  static final RegExp _word = RegExp(r'[a-z]+');

  /// True when the message carries a time reference, which makes a cached
  /// reply wrong rather than merely stale.
  static bool isTimeSensitive(String message) {
    final text = message.toLowerCase();
    // Romanised Bengali/Hindi is how most chats are actually typed, so leaving
    // it out would cache exactly the messages that change fastest.
    const romanised = <String>[
      'kal',
      'aaj',
      'aj',
      'porshu',
      'parshu',
      'ekhon',
      'abhi',
      'subah',
      'sham',
      'shaam',
      'raat',
      'ghonta',
      'ghanta',
      'today',
      'tonight',
      'tomorrow',
      'later',
    ];
    final words = _word.allMatches(text).map((m) => m.group(0)!).toSet();
    if (romanised.any(words.contains)) return true;
    const markers = <String>[
      // Bengali
      'আজ',
      'কাল',
      'পরশু',
      'এখন',
      'সকাল',
      'দুপুর',
      'বিকেল',
      'রাত',
      'সময়',
      'ঘণ্টা',
      'মিনিট',
      // Hindi
      'आज',
      'कल',
      'परसों',
      'अभी',
      'सुबह',
      'दोपहर',
      'शाम',
      'रात',
      'समय',
      'घंटा',
      'मिनट',
      // English
      'today', 'tomorrow', 'yesterday', 'tonight', 'now', 'later', 'morning',
      'evening', 'minute', 'hour', 'o\'clock', 'am ', 'pm ',
    ];
    if (markers.any(text.contains)) return true;
    // A clock time or a date is time-sensitive however it is written.
    return RegExp(r'\b\d{1,2}[:.]\d{2}\b').hasMatch(text) ||
        RegExp(r'\b\d{1,2}[/-]\d{1,2}\b').hasMatch(text);
  }

  /// A cached answer for [request], or null when there is none, it expired, or
  /// the message is time-sensitive.
  CachedReplies? lookup(ReplyRequest request) {
    final box = this.box;
    if (box == null) return null;
    if (isTimeSensitive(request.trimmedMessage)) return null;
    final raw = box.get(keyFor(request));
    if (raw is! Map) return null;
    final storedAt = DateTime.tryParse(raw['at'] as String? ?? '');
    final replies = (raw['replies'] as List?)?.whereType<String>().toList();
    if (storedAt == null || replies == null || replies.isEmpty) return null;
    if (_now().difference(storedAt) > ttl) {
      // Expired: drop it rather than leave it to be found again on next launch.
      box.delete(keyFor(request));
      return null;
    }
    return CachedReplies(replies, storedAt);
  }

  /// Stores [replies] for [request]. Never throws: a cache that cannot write
  /// must not break a generation that already succeeded.
  Future<void> store(ReplyRequest request, List<String> replies) async {
    final box = this.box;
    if (box == null || replies.isEmpty) return;
    if (isTimeSensitive(request.trimmedMessage)) return;
    try {
      await box.put(keyFor(request), {
        'replies': replies,
        'at': _now().toIso8601String(),
      });
      await _prune(box);
    } catch (_) {
      // Deliberately silent: see the doc comment.
    }
  }

  /// Keeps the box bounded. Runs on write rather than on a timer, so a cache
  /// nobody uses costs nothing.
  Future<void> _prune(Box<dynamic> box) async {
    if (box.length <= _maxEntries) return;
    final entries = box.toMap().entries.toList()
      ..sort((a, b) {
        final aAt = (a.value is Map) ? '${(a.value as Map)['at']}' : '';
        final bAt = (b.value is Map) ? '${(b.value as Map)['at']}' : '';
        return aAt.compareTo(bAt);
      });
    final excess = box.length - _maxEntries;
    for (final entry in entries.take(excess)) {
      await box.delete(entry.key);
    }
  }

  Future<void> clear() async {
    await box?.clear();
  }
}
