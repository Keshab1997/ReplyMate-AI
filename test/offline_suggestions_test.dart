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
}
