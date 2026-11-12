import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';
import 'package:replymate/features/memory/domain/memory_recorder.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';

/// The consent and honesty rules of, proven without
/// a store: what may be remembered, what must be refused, and as whose line.
void main() {
  const recorder = MemoryRecorder();
  final now = DateTime.utc(2026, 11, 11, 12);
  const allowlist = {'com.whatsapp'};

  CapturedNotification capture({
    String packageName = 'com.whatsapp',
    String? text = 'kal dekha hobe?',
    String? title = 'Rahim',
    List<String> priorMessages = const <String>[],
    List<String> priorAuthors = const <String>[],
    bool isGroupSummary = false,
    bool mayBeRedacted = false,
    bool isTruncated = false,
    bool isScreenRead = false,
  }) => CapturedNotification(
    packageName: packageName,
    key: 'k',
    title: title,
    text: text,
    priorMessages: priorMessages,
    priorAuthors: priorAuthors,
    isTruncated: isTruncated,
    isGrouped: false,
    isGroupSummary: isGroupSummary,
    mayBeRedacted: mayBeRedacted,
    hasReplyAction: true,
    postedAtMillis: now.millisecondsSinceEpoch,
    isScreenRead: isScreenRead,
  );

  group('a capture', () {
    test('is remembered as the other person\'s line', () {
      final lines = recorder.linesForCapture(
        capture(),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines, hasLength(1));
      expect(lines.single.text, 'kal dekha hobe?');
      expect(lines.single.author, MemoryAuthor.them);
    });

    test('from an app outside the allowlist is refused', () {
      // Wall 2. The native layer filters too; memory gates itself anyway,
      // because a persistence decision should not depend on an upstream check
      // staying correct forever.
      final lines = recorder.linesForCapture(
        capture(packageName: 'com.example.other'),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines, isEmpty);
    });

    test('with no text is refused', () {
      for (final text in <String?>[null, '', '   ']) {
        expect(
          recorder.linesForCapture(
            capture(text: text),
            allowedPackages: allowlist,
            now: now,
          ),
          isEmpty,
        );
      }
    });

    test('that is a group summary is refused', () {
      // "3 new messages" is a count, not something anyone said.
      expect(
        recorder.linesForCapture(
          capture(text: '3 new messages', isGroupSummary: true),
          allowedPackages: allowlist,
          now: now,
        ),
        isEmpty,
      );
    });

    test('that is redacted is refused rather than stored as a placeholder', () {
      // A stored "You have a new message" looks like content and is not.
      expect(
        recorder.linesForCapture(
          capture(text: 'You have a new message', mayBeRedacted: true),
          allowedPackages: allowlist,
          now: now,
        ),
        isEmpty,
      );
    });

    test('truncated content is stored as captured, not repaired', () {
      final lines = recorder.linesForCapture(
        capture(text: 'kal dekha hobe kin…', isTruncated: true),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines.single.text, 'kal dekha hobe kin…');
      // The UI already says "truncated"; memory stores what was actually there.
    });

    test('a screen-read capture is remembered like any other', () {
      final lines = recorder.linesForCapture(
        capture(text: 'screen e ja ache', isScreenRead: true),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines.single.author, MemoryAuthor.them);
    });
  });

  group('history', () {
    test('untagged history is dropped, never guessed', () {
      // The notification path: priorMessages with no author. Storing these
      // would label the user's own words as the sender's.
      final lines = recorder.linesForCapture(
        capture(
          priorMessages: ['amar kotha', 'tomar kotha', 'kal dekha hobe?'],
        ),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines, hasLength(1));
      expect(lines.single.text, 'kal dekha hobe?');
    });

    test('tagged history keeps both sides, in order', () {
      // The screen-reading path, the only one that knows who spoke.
      final lines = recorder.linesForCapture(
        capture(
          text: 'kal dekha hobe?',
          priorMessages: ['amar kotha', 'tomar kotha'],
          priorAuthors: ['them', 'me'],
          isScreenRead: true,
        ),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines.map((line) => line.text), [
        'amar kotha',
        'tomar kotha',
        'kal dekha hobe?',
      ]);
      expect(lines.map((line) => line.author), [
        MemoryAuthor.them,
        MemoryAuthor.me,
        MemoryAuthor.them,
      ]);
    });

    test('the history sits before the newest line, and the newest is last', () {
      final lines = recorder.linesForCapture(
        capture(text: 'newest', priorMessages: ['older'], priorAuthors: ['me']),
        allowedPackages: allowlist,
        now: now,
      );

      // Ordering is expressed in timestamps because a window sorts on them;
      // equal stamps would make the sort arbitrary.
      expect(lines.last.text, 'newest');
      expect(lines.last.at.isAfter(lines.first.at), isTrue);
    });

    test('a misaligned author list is treated as no history at all', () {
      // Half-tagged is not tagged: a length mismatch means the pairing cannot
      // be trusted, so nothing is claimed about who spoke.
      final lines = recorder.linesForCapture(
        capture(priorMessages: ['one', 'two'], priorAuthors: ['me']),
        allowedPackages: allowlist,
        now: now,
      );

      expect(lines, hasLength(1));
    });

    test('too much history keeps the newest lines', () {
      const small = MemoryRecorder(policy: MemoryPolicy(maxLinesPerContact: 3));
      final lines = small.linesForCapture(
        capture(
          text: 'now',
          priorMessages: ['one', 'two', 'three', 'four'],
          priorAuthors: ['them', 'them', 'them', 'them'],
        ),
        allowedPackages: allowlist,
        now: now,
      );

      // Cap counts history only; the message being answered is always kept.
      expect(lines.map((line) => line.text), ['two', 'three', 'four', 'now']);
    });
  });

  group('an accepted reply', () {
    test('is the user\'s own voice, verbatim', () {
      final line = recorder.lineForAcceptedReply(
        'haa aschi, ektu deri hobe',
        now: now,
      );

      expect(line!.author, MemoryAuthor.me);
      expect(line.text, 'haa aschi, ektu deri hobe');
    });

    test('is trimmed', () {
      final line = recorder.lineForAcceptedReply('  ok aschi  ', now: now);

      expect(line!.text, 'ok aschi');
    });

    test('is refused when empty', () {
      for (final text in <String?>[null, '', '  \n ']) {
        expect(recorder.lineForAcceptedReply(text, now: now), isNull);
      }
    });
  });

  group('apply', () {
    final key = ConversationKey.tryOf(
      packageName: 'com.whatsapp',
      contactName: 'Rahim',
    )!;

    test('leaves the window untouched when nothing was recorded', () {
      final memory = ConversationMemory.empty(key: key);

      final after = recorder.apply(memory, const <MemoryLine>[], now: now);

      expect(identical(after, memory), isTrue);
      expect(after.isEmpty, isTrue);
    });

    test('adds every line it is given', () {
      final memory = ConversationMemory.empty(key: key);
      final line = recorder.lineForAcceptedReply('aschi', now: now);

      final after = recorder.apply(memory, <MemoryLine>[line!], now: now);

      expect(after.lines, hasLength(1));
      expect(after.lines.single.author, MemoryAuthor.me);
    });
  });
}
