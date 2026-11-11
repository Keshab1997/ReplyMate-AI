import '../../notifications/models/captured_notification.dart';
import 'conversation_memory.dart';

/// Decides *whether* something may enter conversation memory, and as whose line.
///
/// Kept apart from the store and from Riverpod so the rules are provable without
/// a box, a widget or a platform channel - the store is about persistence, this
/// is about consent and honesty.
class MemoryRecorder {
  const MemoryRecorder({this.policy = MemoryPolicy.standard});

  final MemoryPolicy policy;

  /// Every line a capture contributes, oldest first - possibly none.
  ///
  /// [allowedPackages] is the user's app allowlist. The native layer already
  /// filters by it; memory checks again because a *persistence* decision
  /// deserves its own gate rather than trusting an upstream one to stay correct
  /// forever (docs/CONVERSATION_MEMORY.md §3, wall 2).
  ///
  /// History is stored **only when the capture tagged it**. A notification's
  /// priorMessages carry no author, so writing them would label the user's own
  /// words as the other person's; only the screen reader can say which bubble
  /// was whose (`priorAuthors`, docs/CONVERSATION_MEMORY.md §8). Untagged
  /// history is therefore dropped, not guessed at.
  ///
  /// The newest line is always [MemoryAuthor.them], a claim this method can back
  /// up: a capture only exists when there is something to answer, and both
  /// sources suppress the case where the newest message is the user's own.
  List<MemoryLine> linesForCapture(
    CapturedNotification capture, {
    required Set<String> allowedPackages,
    required DateTime now,
  }) {
    if (!allowedPackages.contains(capture.packageName)) return const [];

    final text = (capture.text ?? '').trim();
    if (text.isEmpty) return const [];

    // A group summary is a count ("3 new messages"), not a sentence anyone
    // said. Remembering it would put a line in the conversation that no
    // participant ever typed.
    if (capture.isGroupSummary) return const [];

    // "You have a new message" tells the model nothing about the conversation,
    // and a stored placeholder is worse than an absent line: it looks like
    // content.
    if (capture.mayBeRedacted) return const [];

    final lines = <MemoryLine>[];

    if (capture.hasTaggedHistory) {
      final history = _taggedHistory(capture);
      // Keep the newest of the history when it is too long: the messages just
      // before the one being answered are the ones that matter.
      final kept = history.length > policy.maxLinesPerContact
          ? history.sublist(history.length - policy.maxLinesPerContact)
          : history;

      // The wire carries no timestamps for history, so the order is expressed
      // in the only field that survives a sort: each line sits a second before
      // the next, and the message being answered sits at `now`. Relative order
      // is all a window needs, and it is not invented content.
      for (var index = 0; index < kept.length; index++) {
        final offset = kept.length - index;
        lines.add(
          MemoryLine(
            text: kept[index].$1,
            author: kept[index].$2,
            at: now.subtract(Duration(seconds: offset)),
          ),
        );
      }
    }

    lines.add(MemoryLine(text: text, author: MemoryAuthor.them, at: now));
    return lines;
  }

  /// Pairs each tagged history line with its author, dropping blanks.
  List<(String, MemoryAuthor)> _taggedHistory(CapturedNotification capture) {
    final out = <(String, MemoryAuthor)>[];
    for (var index = 0; index < capture.priorMessages.length; index++) {
      final text = capture.priorMessages[index].trim();
      if (text.isEmpty) continue;
      final author = capture.priorAuthors[index] == 'me'
          ? MemoryAuthor.me
          : MemoryAuthor.them;
      out.add((text, author));
    }
    return out;
  }

  /// The line a reply the user accepted contributes: their own voice, verbatim.
  ///
  /// This is the only reliable source of `me` lines today. Screen reading can
  /// see sent bubbles, but the wire format does not say which line is whose, so
  /// voice examples come from what this app composed and the user chose to send
  /// (docs/CONVERSATION_MEMORY.md §8).
  MemoryLine? lineForAcceptedReply(String? text, {required DateTime now}) {
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) return null;
    return MemoryLine(text: trimmed, author: MemoryAuthor.me, at: now);
  }

  /// Applies the lines a capture or a reply produced. Returns the same window
  /// when there was nothing to add, so a caller can skip the write instead of
  /// rewriting identical bytes.
  ConversationMemory apply(
    ConversationMemory memory,
    List<MemoryLine> lines, {
    required DateTime now,
  }) {
    if (lines.isEmpty) return memory;
    var next = memory;
    for (final line in lines) {
      next = next.append(line, now: now);
    }
    return next;
  }
}
