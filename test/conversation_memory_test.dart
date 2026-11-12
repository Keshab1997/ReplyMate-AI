import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';

/// Proves the four numbered promises of that can
/// be proven without a device: the cap evicts the *oldest*, age expiry drops the
/// stale, a long paste cannot eat the budget, and the voice examples really do
/// come from the user's own lines only.
/// A tiny policy keeps each rule visible instead of building forty lines to
/// discover what happens at forty-one.
void main() {
  const tiny = MemoryPolicy(
    maxLinesPerContact: 3,
    maxLineLength: 40,
    maxAge: Duration(days: 2),
    styleExampleCount: 2,
    minStyleExampleLength: 10,
  );

  final now = DateTime.utc(2026, 11, 11, 12);
  final key = ConversationKey.tryOf(
    packageName: 'com.whatsapp',
    contactName: 'Rahim',
  )!;

  MemoryLine them(String text, {int minutesAgo = 0}) => MemoryLine(
    text: text,
    author: MemoryAuthor.them,
    at: now.subtract(Duration(minutes: minutesAgo)),
  );

  MemoryLine me(String text, {int minutesAgo = 0}) => MemoryLine(
    text: text,
    author: MemoryAuthor.me,
    at: now.subtract(Duration(minutes: minutesAgo)),
  );

  group('ConversationKey', () {
    test('trims the halves it is given', () {
      final trimmed = ConversationKey.tryOf(
        packageName: '  com.whatsapp ',
        contactName: ' Rahim  ',
      )!;
      expect(trimmed.packageName, 'com.whatsapp');
      expect(trimmed.contactName, 'Rahim');
      expect(trimmed.id, 'com.whatsapp::Rahim');
    });

    test('refuses a missing package or sender instead of filing a bucket', () {
      // A nameless bucket would mix every anonymous notification into one
      // contact's memory - the worst possible failure for this feature.
      expect(
        ConversationKey.tryOf(packageName: 'com.whatsapp', contactName: null),
        isNull,
      );
      expect(
        ConversationKey.tryOf(packageName: '', contactName: 'Rahim'),
        isNull,
      );
      expect(
        ConversationKey.tryOf(packageName: 'com.whatsapp', contactName: '   '),
        isNull,
      );
    });
  });

  group('the cap keeps the newest', () {
    test('evicts the oldest line, never today\'s message', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          them('one', minutesAgo: 4),
          them('two', minutesAgo: 3),
          them('three', minutesAgo: 2),
          them('four', minutesAgo: 1),
          them('five', minutesAgo: 0),
        ],
      );

      expect(memory.lines.length, tiny.maxLinesPerContact);
      // 'one' and 'two' went; the newest is still there. A full store that
      // dropped the newest would be a store that stopped answering.
      expect(memory.lines.map((line) => line.text), ['three', 'four', 'five']);
    });

    test('a re-posted notification is one message, not two', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          them('same thing', minutesAgo: 2),
          them('same thing', minutesAgo: 1),
        ],
      );

      expect(memory.lines.length, 1);
    });

    test('the same words from the two sides are two messages', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [them('ok', minutesAgo: 2), me('ok', minutesAgo: 1)],
      );

      expect(memory.lines.length, 2);
    });
  });

  group('expiry', () {
    test('drops a line older than the policy allows', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          them('stale', minutesAgo: 60 * 24 * 3),
          them('fresh', minutesAgo: 30),
        ],
      );

      expect(memory.lines.map((line) => line.text), ['fresh']);
    });

    test('keeps a line that is inside the window', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [them('recent', minutesAgo: 60)],
      );

      expect(memory.lines, hasLength(1));
    });

    test(
      'a line with no usable timestamp is treated as ancient, not as now',
      () {
        // Reading a missing timestamp as "now" would silently promote junk into
        // the freshest context - the opposite of honest.
        final memory = ConversationMemory.fromStored(
          key: key,
          now: now,
          policy: tiny,
          lines: [
            MemoryLine(
              text: 'no clock',
              author: MemoryAuthor.them,
              at: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ],
        );

        expect(memory.isEmpty, isTrue);
      },
    );
  });

  group('line length', () {
    test('truncates a pasted essay and marks it', () {
      // Its own policy: the length limit deserves a fixture where the limit is
      // the only thing in play, not a side effect of the shared one.
      const shortLines = MemoryPolicy(
        maxLineLength: 20,
        maxAge: Duration(days: 2),
      );
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: shortLines,
        lines: [them('x' * 200)],
      );

      final text = memory.lines.single.text;
      expect(text.length, shortLines.maxLineLength + 1); // + the ellipsis
      expect(text.endsWith('…'), isTrue);
    });

    test('blank lines are not stored', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [them('   '), them('')],
      );

      expect(memory.isEmpty, isTrue);
    });
  });

  group('what the prompt gets', () {
    test('context lines say who spoke, oldest first', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          me('kal asbo bolechilam', minutesAgo: 3),
          them('tahole kal dekha hobe', minutesAgo: 2),
        ],
      );

      expect(memory.contextLines(), [
        'me: kal asbo bolechilam',
        'them: tahole kal dekha hobe',
      ]);
    });

    test('context can be limited to the newest lines', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          them('first message', minutesAgo: 3),
          them('second message', minutesAgo: 2),
          them('third message', minutesAgo: 1),
        ],
      );

      expect(memory.contextLines(max: 2), [
        'them: second message',
        'them: third message',
      ]);
    });

    test('voice examples come only from the user', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          them('are you coming today or not', minutesAgo: 3),
          me('haa aschi, ekটু deri hobe', minutesAgo: 2),
        ],
      );

      expect(memory.styleExamples(), ['haa aschi, ekটু deri hobe']);
      expect(memory.hasVoiceEvidence, isTrue);
    });

    test('a one-word reply is not offered as a style example', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [me('ok', minutesAgo: 2)],
      );

      expect(memory.styleExamples(), isEmpty);
      // The context is still there - short is fine to remember, just not to
      // imitate.
      expect(memory.contextLines(), hasLength(1));
    });

    test('no user lines at all means no voice claim', () {
      // This is the screen-reading-off case: arrivals only.
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [them('hello hello', minutesAgo: 1)],
      );

      expect(memory.styleExamples(), isEmpty);
      expect(memory.hasVoiceEvidence, isFalse);
    });

    test('offers at most the policy count, newest first', () {
      final memory = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          me('first proper sentence', minutesAgo: 3),
          me('second proper sentence', minutesAgo: 2),
          me('third proper sentence', minutesAgo: 1),
        ],
      );

      expect(memory.styleExamples(), [
        'third proper sentence',
        'second proper sentence',
      ]);
    });
  });

  group('append', () {
    test('returns a new window and leaves the old one alone', () {
      final before = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [them('first message', minutesAgo: 1)],
      );

      final after = before.append(them('second message'), now: now);

      expect(before.lines, hasLength(1));
      expect(after.lines, hasLength(2));
      expect(after.lines.last.text, 'second message');
    });

    test('re-applies the cap', () {
      var memory = ConversationMemory.empty(key: key, policy: tiny);
      for (var i = 0; i < 10; i++) {
        memory = memory.append(
          them('message $i'),
          now: now.add(Duration(minutes: i)),
        );
      }

      expect(memory.lines, hasLength(tiny.maxLinesPerContact));
      expect(memory.lines.last.text, 'message 9');
    });
  });

  group('storage round trip', () {
    test('a window survives toJson and back', () {
      final original = ConversationMemory.fromStored(
        key: key,
        now: now,
        policy: tiny,
        lines: [
          them('kal dekha hobe', minutesAgo: 2),
          me('haa thik ache bhai', minutesAgo: 1),
        ],
      );

      final restored = ConversationMemory.fromJson(
        original.toJson(),
        key: key,
        now: now,
        policy: tiny,
      )!;

      expect(restored.lines.map((line) => line.text), [
        'kal dekha hobe',
        'haa thik ache bhai',
      ]);
      expect(restored.lines.last.author, MemoryAuthor.me);
    });

    test('one corrupt line does not cost the rest', () {
      final restored = ConversationMemory.fromJson(
        {
          'key': key.id,
          'lines': [
            {
              'text': 'good line here',
              'author': 'them',
              'at': now.toIso8601String(),
            },
            {'text': '', 'author': 'them'},
            {'nonsense': true},
            {
              'text': 'another good one',
              'author': 'me',
              'at': now.toIso8601String(),
            },
          ],
        },
        key: key,
        now: now,
        policy: tiny,
      )!;

      expect(restored.lines.map((line) => line.text), [
        'good line here',
        'another good one',
      ]);
    });

    test('an empty or missing line list is an empty window, not a throw', () {
      for (final payload in <Map<Object?, Object?>>[
        {'key': key.id},
        {'key': key.id, 'lines': <Object?>[]},
        {'key': key.id, 'lines': 'not a list'},
      ]) {
        final memory = ConversationMemory.fromJson(
          payload,
          key: key,
          now: now,
          policy: tiny,
        )!;
        expect(memory.isEmpty, isTrue);
        // The promise that matters: an unreadable store still generates.
        expect(memory.contextLines(), isEmpty);
      }
    });
  });
}
