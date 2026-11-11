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

  /// The line a capture contributes, or null when it contributes nothing.
  ///
  /// [allowedPackages] is the user's app allowlist. The native layer already
  /// filters by it; memory checks again because a *persistence* decision
  /// deserves its own gate rather than trusting an upstream one to stay correct
  /// forever (docs/CONVERSATION_MEMORY.md §3, wall 2).
  ///
  /// The author is always [MemoryAuthor.them], and that is a claim this method
  /// can actually stand behind: a capture only exists when there is something
  /// to answer, and both sources suppress the case where the newest message is
  /// the user's own. The capture's own `priorMessages` are deliberately **not**
  /// stored - the wire carries no per-line author, so writing them would label
  /// the user's words as the other person's. That is exactly the kind of quiet
  /// wrongness this feature cannot afford.
  MemoryLine? lineForCapture(
    CapturedNotification capture, {
    required Set<String> allowedPackages,
    required DateTime now,
  }) {
    if (!allowedPackages.contains(capture.packageName)) return null;

    final text = (capture.text ?? '').trim();
    if (text.isEmpty) return null;

    // A group summary is a count ("3 new messages"), not a sentence anyone
    // said. Remembering it would put a line in the conversation that no
    // participant ever typed.
    if (capture.isGroupSummary) return null;

    // "You have a new message" tells the model nothing about the conversation,
    // and a stored placeholder is worse than an absent line: it looks like
    // content.
    if (capture.mayBeRedacted) return null;

    return MemoryLine(text: text, author: MemoryAuthor.them, at: now);
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

  /// Applies a line to a window, if there is one. Returns the same window when
  /// nothing changed, so a caller can skip the write.
  ConversationMemory apply(
    ConversationMemory memory,
    MemoryLine? line, {
    required DateTime now,
  }) {
    if (line == null) return memory;
    return memory.append(line, now: now);
  }
}
