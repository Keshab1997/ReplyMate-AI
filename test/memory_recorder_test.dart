import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';
import 'package:replymate/features/memory/domain/memory_recorder.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';

/// The consent and honesty rules of docs/CONVERSATION_MEMORY.md, proven without
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
      final line = recorder.lineForCapture(
        capture(),
        allowedPackages: allowlist,
        now: now,
      );

      expect(line, isNotNull);
      expect(line!.text, 'kal dekha hobe?');
      expect(line.author, MemoryAuthor.them);
    });

    test('from an app outside the allowlist is refused', () {
      // Wall 2. The native layer filters too; memory gates itself anyway,
      // because a persistence decision should not depend on an upstream check
      // staying correct forever.
      final line = recorder.lineForCapture(
        capture(packageName: 'com.example.other'),
        allowedPackages: allowlist,
        now: now,
      );

      expect(line, isNull);
    });

    test('with no text is refused', () {
      for (final text in <String?>[null, '', '   ']) {
        expect(
          recorder.lineForCapture(
            capture(text: text),
            allowedPackages: allowlist,
            now: now,
          ),
          isNull,
        );
      }
    });

    test('that is a group summary is refused', () {
      // "3 new messages" is a count, not something anyone said.
      expect(
        recorder.lineForCapture(
          capture(text: '3 new messages', isGroupSummary: true),
          allowedPackages: allowlist,
          now: now,
        ),
        isNull,
      );
    });

    test('that is redacted is refused rather than stored as a placeholder', () {
      // A stored "You have a new message" looks like content and is not.
      expect(
        recorder.lineForCapture(
          capture(text: 'You have a new message', mayBeRedacted: true),
          allowedPackages: allowlist,
          now: now,
        ),
        isNull,
      );
    });

    test('keeps exactly one line and never the untagged history', () {
      // The wire carries no per-line author, so storing priorMessages would
      // label the user's own words as the sender's. One capture, one line.
      final line = recorder.lineForCapture(
        capture(
          priorMessages: ['amar kotha', 'tomar kotha', 'kal dekha hobe?'],
        ),
        allowedPackages: allowlist,
        now: now,
      );

      expect(line!.text, 'kal dekha hobe?');
    });

    test('truncated content is stored as captured, not repaired', () {
      final line = recorder.lineForCapture(
        capture(text: 'kal dekha hobe kin…', isTruncated: true),
        allowedPackages: allowlist,
        now: now,
      );

      expect(line!.text, 'kal dekha hobe kin…');
      // The UI already says "truncated"; memory stores what was actually there.
    });

    test('a screen-read capture is remembered like any other', () {
      final line = recorder.lineForCapture(
        capture(text: 'screen e ja ache', isScreenRead: true),
        allowedPackages: allowlist,
        now: now,
      );

      expect(line!.author, MemoryAuthor.them);
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

      final after = recorder.apply(memory, null, now: now);

      expect(identical(after, memory), isTrue);
      expect(after.isEmpty, isTrue);
    });

    test('adds the line when there is one', () {
      final memory = ConversationMemory.empty(key: key);
      final line = recorder.lineForAcceptedReply('aschi', now: now);

      final after = recorder.apply(memory, line, now: now);

      expect(after.lines, hasLength(1));
      expect(after.lines.single.author, MemoryAuthor.me);
    });
  });
}
