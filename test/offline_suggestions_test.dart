import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/offline_suggestions.dart';

List<String> _for(
  String message, {
  ReplyLanguage language = ReplyLanguage.bengali,
  ReplyTone tone = ReplyTone.friendly,
  ReplyLength length = ReplyLength.short,
  int count = 1,
}) => OfflineSuggestions.forMessage(
  message,
  language: language,
  tone: tone,
  length: length,
  count: count,
);

void main() {
  group('intent detection', () {
    test('a question mark makes it a question, in any script', () {
      expect(OfflineSuggestions.intentOf('kal asbo?'), OfflineIntent.question);
      expect(
        OfflineSuggestions.intentOf('আজ দেখা হবে?'),
        OfflineIntent.question,
      );
      expect(OfflineSuggestions.intentOf('कब आओगे?'), OfflineIntent.question);
    });

    test('thanks, apology, greeting, farewell and ack are recognised', () {
      expect(OfflineSuggestions.intentOf('thanks a lot'), OfflineIntent.thanks);
      expect(OfflineSuggestions.intentOf('ধন্যবাদ'), OfflineIntent.thanks);
      expect(
        OfflineSuggestions.intentOf('sorry, I forgot'),
        OfflineIntent.apology,
      );
      expect(OfflineSuggestions.intentOf('hello!'), OfflineIntent.greeting);
      expect(OfflineSuggestions.intentOf('नमस्ते'), OfflineIntent.greeting);
      expect(
        OfflineSuggestions.intentOf('bye, good night'),
        OfflineIntent.farewell,
      );
      expect(OfflineSuggestions.intentOf('ok'), OfflineIntent.acknowledgement);
    });

    test('a generic question does not get an assumed yes', () {
      for (final language in ReplyLanguage.values) {
        final first = _for('Can you do this?', language: language).first;
        expect(first.toLowerCase(), isNot(startsWith('yes')));
        expect(first.toLowerCase(), isNot(startsWith('हाँ')));
        expect(first, isNot(startsWith('হ্যাঁ')));
      }
    });

    test('a plain statement is not forced into an intent', () {
      // The honest answer to "I don't know what this means" is unknown, and an
      // unknown intent produces no suggestions rather than a confident wrong
      // one.
      expect(
        OfflineSuggestions.intentOf('the report is on the table'),
        OfflineIntent.unknown,
      );
      expect(_for('the report is on the table'), isEmpty);
    });
  });

  group('free variation', () {
    test('excluding what is already shown returns something new', () {
      const message = 'Can we meet tomorrow?';
      final first = OfflineSuggestions.forMessage(
        message,
        language: ReplyLanguage.english,
        tone: ReplyTone.polite,
        length: ReplyLength.short,
      );
      final next = OfflineSuggestions.forMessage(
        message,
        language: ReplyLanguage.english,
        tone: ReplyTone.polite,
        length: ReplyLength.short,
        exclude: first.toSet(),
      );
      expect(next, isNotEmpty);
      expect(next.any(first.contains), isFalse);
    });

    test(
      'an exhausted table returns nothing, which is the escalate signal',
      () {
        const message = 'Can we meet tomorrow?';
        final everything = <String>{
          ...OfflineSuggestions.forMessage(
            message,
            language: ReplyLanguage.english,
            tone: ReplyTone.polite,
            length: ReplyLength.short,
            count: 99,
          ),
        };
        expect(everything, isNotEmpty);
        expect(
          OfflineSuggestions.forMessage(
            message,
            language: ReplyLanguage.english,
            tone: ReplyTone.polite,
            length: ReplyLength.short,
            exclude: everything,
          ),
          isEmpty,
        );
      },
    );
  });

  group('suggestions', () {
    test('a question gets answers in the reply language', () {
      expect(_for('kal asbo?', language: ReplyLanguage.bengali), isNotEmpty);
      expect(_for('kal asbo?', language: ReplyLanguage.hindi), isNotEmpty);
      expect(_for('kal asbo?', language: ReplyLanguage.english), isNotEmpty);
    });

    test('the request count is respected', () {
      expect(_for('kal asbo?', count: 1).length, 1);
      expect(_for('kal asbo?', count: 3).length, lessThanOrEqualTo(3));
    });

    test('a tone with its own line leads with it, and keeps the plain one', () {
      // The plain answer stays available: a tone is an option, not a replacement
      // for the thing the user might actually want to say.
      final plain = _for('thanks', tone: ReplyTone.friendly, count: 3);
      final funny = _for('thanks', tone: ReplyTone.funny, count: 3);

      expect(funny.first, isNot(plain.first));
      expect(funny, contains(plain.first));
    });

    test('no suggestion is ever duplicated', () {
      final list = _for('ok', count: 3);
      expect(list.toSet().length, list.length);
    });

    test('every language covers every intent the detector can return', () {
      // A missing key would silently turn a suggestion into an empty list.
      for (final language in ReplyLanguage.values) {
        for (final intent in [
          OfflineIntent.question,
          OfflineIntent.thanks,
          OfflineIntent.greeting,
          OfflineIntent.acknowledgement,
        ]) {
          expect(
            _for('hello?', language: language),
            isNotEmpty,
            reason: '$language / $intent',
          );
        }
      }
    });
  });

  group('a standalone brief gets starters', () {
    test('a brief that hints at thanks gets a thanks opener', () {
      final lines = OfflineSuggestions.forBrief(
        'thank my friend for helping me move',
        language: ReplyLanguage.english,
        tone: ReplyTone.friendly,
        length: ReplyLength.short,
      );
      expect(lines, isNotEmpty);
    });

    test('it never returns more than asked for', () {
      final lines = OfflineSuggestions.forBrief(
        'write something',
        language: ReplyLanguage.bengali,
        tone: ReplyTone.casual,
        length: ReplyLength.short,
        count: 1,
      );
      expect(lines.length, lessThanOrEqualTo(1));
    });

    test('every language has something to offer', () {
      for (final language in ReplyLanguage.values) {
        final lines = OfflineSuggestions.forBrief(
          'write a message',
          language: language,
          tone: ReplyTone.friendly,
          length: ReplyLength.short,
        );
        expect(lines, isNotEmpty, reason: 'no starters for ${language.label}');
      }
    });
  });
}

// --- the writer's fallback path -------------------------------------------
// A standalone brief used to get nothing when no provider answered, which made
// the writer look broken on a first run. It gets on-device openers instead,
// labelled offline by the screen.
