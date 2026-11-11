import 'dart:math' as math;

/// The caps and expiry that keep conversation memory a window instead of a
/// record (docs/CONVERSATION_MEMORY.md §4).
///
/// They live in one object so a test can hand in a tiny policy and prove the
/// eviction rules in milliseconds, instead of building forty lines to find out
/// what happens at forty-one. Nothing here reads the clock: `now` is passed in,
/// because a store whose expiry depends on when you happen to call it cannot be
/// tested at all.
class MemoryPolicy {
  const MemoryPolicy({
    this.maxLinesPerContact = 40,
    this.maxContacts = 50,
    this.maxLineLength = 500,
    this.maxAge = const Duration(days: 7),
    this.styleExampleCount = 3,
    this.minStyleExampleLength = 12,
  });

  /// The shipped limits. Changing a number here is a doc change too - §4 of
  /// docs/CONVERSATION_MEMORY.md is the table the user is promised.
  static const MemoryPolicy standard = MemoryPolicy();

  /// Oldest lines are evicted past this; the newest always survive.
  final int maxLinesPerContact;

  /// Contacts kept. The store is a working set, not an archive.
  final int maxContacts;

  /// One pasted essay must not become the whole budget of a conversation.
  final int maxLineLength;

  /// How long a line stays worth answering in context.
  final Duration maxAge;

  /// Few-shot examples of the user's own voice. Past three they crowd out the
  /// message actually being answered.
  final int styleExampleCount;

  /// A one-word "ok" teaches the model nothing about how someone writes, so it
  /// is not offered as an example of anything.
  final int minStyleExampleLength;
}

/// Who said a stored line.
enum MemoryAuthor {
  /// The other person - the side being answered.
  them,

  /// The user. The only source of the voice half of this feature.
  me;

  static MemoryAuthor fromWire(Object? raw) =>
      raw == 'me' ? MemoryAuthor.me : MemoryAuthor.them;
}

/// One stored message.
class MemoryLine {
  const MemoryLine({
    required this.text,
    required this.author,
    required this.at,
  });

  factory MemoryLine.fromJson(Map<Object?, Object?> json) {
    final text = json['text'];
    final at = json['at'];
    if (text is! String || text.trim().isEmpty) {
      throw const FormatException('memory line without text');
    }
    // An unparseable timestamp is not worth refusing a line over: the text is
    // the part the user cares about, and `now` will decide its age anyway.
    final when = at is String ? DateTime.tryParse(at) : null;
    return MemoryLine(
      text: text,
      author: MemoryAuthor.fromWire(json['author']),
      at: when ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String text;
  final MemoryAuthor author;
  final DateTime at;

  /// Neutral wording: the model is told who spoke, not what to assume about
  /// them. "me" and "them" is a fact; "friend" or "boss" would be an invention.
  String get promptLabel => author == MemoryAuthor.me ? 'me' : 'them';

  Map<String, Object?> toJson() => {
    'text': text,
    'author': author == MemoryAuthor.me ? 'me' : 'them',
    'at': at.toIso8601String(),
  };

  @override
  String toString() => '$promptLabel: $text';
}

/// What a memory is filed under.
///
/// A notification's sender name is a **display name, not a contact identity**
/// (docs/CONVERSATION_MEMORY.md §5): a rename starts a new memory, a group chat
/// files under the group, and two contacts sharing a display name share one
/// memory. That is a known, documented weakness - not something this class
/// papers over with a fingerprint that would still be guessing.
class ConversationKey {
  const ConversationKey._(this.packageName, this.contactName);

  /// Null when either half is unusable, so a caller cannot accidentally file
  /// every anonymous notification under one nameless bucket.
  static ConversationKey? tryOf({
    required String? packageName,
    required String? contactName,
  }) {
    final package = (packageName ?? '').trim();
    final contact = (contactName ?? '').trim();
    if (package.isEmpty || contact.isEmpty) return null;
    return ConversationKey._(package, contact);
  }

  final String packageName;
  final String contactName;

  /// Stable storage id. Deliberately readable: hashing it would protect nothing
  /// while the message text sits next to it in the same store, and an opaque id
  /// makes "delete this one" and a debug dump both harder than they should be.
  String get id => '$packageName::$contactName';

  @override
  bool operator ==(Object other) =>
      other is ConversationKey &&
      other.packageName == packageName &&
      other.contactName == contactName;

  @override
  int get hashCode => Object.hash(packageName, contactName);

  @override
  String toString() => id;
}

/// A bounded, per-contact window of a conversation plus the voice examples
/// drawn from the user's own lines.
///
/// Immutable: [append] and [fromStored] return a new window with the policy
/// applied. That is what makes every eviction rule in §4 a one-line unit test
/// instead of an integration test against a database.
class ConversationMemory {
  ConversationMemory._(this.key, this.lines, this.policy);

  /// Builds a window from whatever the store had, applying caps and expiry.
  factory ConversationMemory.fromStored({
    required ConversationKey key,
    required Iterable<MemoryLine> lines,
    required DateTime now,
    MemoryPolicy policy = MemoryPolicy.standard,
  }) {
    return ConversationMemory._(
      key,
      _normalize(lines, now: now, policy: policy),
      policy,
    );
  }

  /// An empty window - what "memory off", "store unreadable" and "brand new
  /// contact" all look like, and each of them must still generate a reply.
  factory ConversationMemory.empty({
    required ConversationKey key,
    MemoryPolicy policy = MemoryPolicy.standard,
  }) => ConversationMemory._(key, const <MemoryLine>[], policy);

  final ConversationKey key;

  /// Oldest first, already capped, expired dropped and blanks removed.
  final List<MemoryLine> lines;

  final MemoryPolicy policy;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// The user's own lines in this window - the only raw material the voice half
  /// of this feature has.
  int get ownLineCount =>
      lines.where((line) => line.author == MemoryAuthor.me).length;

  /// True when this window can say anything about how the user writes. False is
  /// the honest answer with screen reading off: notification capture only ever
  /// sees arrivals (docs/CONVERSATION_MEMORY.md §8).
  bool get hasVoiceEvidence => styleExamples().isNotEmpty;

  /// Adds one line to the newest end and re-applies the window.
  ///
  /// Appending to the past is a caller bug, not something to silently repair,
  /// but it must not corrupt the order either - [fromStored] sorts, so an
  /// out-of-order line lands where its timestamp says it belongs.
  ConversationMemory append(MemoryLine line, {required DateTime now}) {
    return ConversationMemory.fromStored(
      key: key,
      lines: <MemoryLine>[...lines, line],
      now: now,
      policy: policy,
    );
  }

  /// What the prompt calls the conversation so far: one line per message,
  /// tagged with who spoke so the model answers the right side.
  List<String> contextLines({int? max}) {
    if (lines.isEmpty) return const <String>[];
    final limit = max == null ? lines.length : math.min(max, lines.length);
    final start = math.max(0, lines.length - limit);
    return <String>[
      for (final line in lines.sublist(start))
        '${line.promptLabel}: ${line.text}',
    ];
  }

  /// At most [MemoryPolicy.styleExampleCount] of the user's own lines, shortest
  /// path to "write it the way I write it".
  ///
  /// Newest first: the most recent thing someone typed is the closest thing
  /// there is to how they talk today, and a year-old register is a trap.
  List<String> styleExamples() {
    final mine = <String>[
      for (final line in lines.reversed)
        if (line.author == MemoryAuthor.me &&
            line.text.trim().length >= policy.minStyleExampleLength)
          line.text,
    ];
    return mine.take(policy.styleExampleCount).toList(growable: false);
  }

  Map<String, Object?> toJson() => {
    'key': key.id,
    'lines': <Object?>[for (final line in lines) line.toJson()],
  };

  /// Rehydrates one contact's window. A malformed line is dropped rather than
  /// throwing: one unreadable record must never cost the user the rest of their
  /// context, let alone the reply they asked for.
  static ConversationMemory? fromJson(
    Map<Object?, Object?> json, {
    required ConversationKey key,
    required DateTime now,
    MemoryPolicy policy = MemoryPolicy.standard,
  }) {
    final raw = json['lines'];
    final parsed = <MemoryLine>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        try {
          parsed.add(MemoryLine.fromJson(entry));
        } on FormatException {
          continue;
        }
      }
    }
    return ConversationMemory.fromStored(
      key: key,
      lines: parsed,
      now: now,
      policy: policy,
    );
  }

  static List<MemoryLine> _normalize(
    Iterable<MemoryLine> raw, {
    required DateTime now,
    required MemoryPolicy policy,
  }) {
    final cutoff = now.subtract(policy.maxAge);
    final kept = <MemoryLine>[];
    for (final line in raw) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      // Expiry is about the line's own time, so a clock that jumps backwards
      // cannot resurrect a month-old conversation.
      if (line.at.isBefore(cutoff)) continue;
      kept.add(
        MemoryLine(
          text: text.length <= policy.maxLineLength
              ? text
              : '${text.substring(0, policy.maxLineLength)}…',
          author: line.author,
          at: line.at,
        ),
      );
    }

    // Sort before deduping: "consecutive" only means something once the order
    // is known, and the store hands lines back in insertion order.
    kept.sort((a, b) => a.at.compareTo(b.at));

    final deduped = <MemoryLine>[];
    for (final line in kept) {
      final previous = deduped.isEmpty ? null : deduped.last;
      // A repeated capture of the same line (a re-posted notification) is one
      // message said once, not two.
      if (previous != null &&
          previous.text == line.text &&
          previous.author == line.author) {
        continue;
      }
      deduped.add(line);
    }

    if (deduped.length <= policy.maxLinesPerContact) return deduped;
    return deduped.sublist(deduped.length - policy.maxLinesPerContact);
  }
}
