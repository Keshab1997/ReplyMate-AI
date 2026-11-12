import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

void main() {
  ReplyRequest request({
    String message = 'Can we meet tomorrow?',
    int count = 3,
  }) => ReplyRequest(
    message: message,
    language: ReplyLanguage.bengali,
    tone: ReplyTone.professional,
    length: ReplyLength.short,
    count: count,
  );

  group('ReplyRequest.validate', () {
    test('a well-formed request has no problems', () {
      expect(request().validate(), isEmpty);
      expect(request().isValid, isTrue);
    });

    test('empty and whitespace-only messages are rejected', () {
      expect(request(message: '').validate(), hasLength(1));
      expect(request(message: '   \n ').validate(), hasLength(1));
    });

    test('oversized messages are rejected with the limit in the message', () {
      final problems = request(message: 'a' * 4001).validate();
      expect(problems, hasLength(1));
      expect(problems.single, contains('4000'));
    });

    test('the 4000-character boundary is allowed', () {
      expect(request(message: 'a' * 4000).validate(), isEmpty);
    });

    test('suggestion count outside 1..3 is rejected', () {
      expect(request(count: 0).validate(), hasLength(1));
      expect(request(count: 4).validate(), hasLength(1));
      expect(request(count: 1).validate(), isEmpty);
    });

    test('surrounding whitespace is trimmed before sending', () {
      expect(request(message: '  hello  ').trimmedMessage, 'hello');
    });
  });

  group('ReplyRequest.toJson', () {
    test('matches the documented request shape', () {
      expect(request().toJson(), {
        'message': 'Can we meet tomorrow?',
        'language': 'Bengali',
        'tone': 'Professional',
        'length': 'Short',
        'count': 3,
        'priorMessages': const <String>[],
        'styleExamples': const <String>[],
      });
    });
  });

  group('option enums', () {
    test('all six FR-06 tones exist, plus the two partner voices', () {
      expect(ReplyTone.values, hasLength(8));
      expect(
        ReplyTone.values.map((tone) => tone.label),
        containsAll(<String>[
          'Friendly',
          'Casual',
          'Professional',
          'Polite',
          'Funny',
          'Short and direct',
          'Premika',
          'Premik',
        ]),
      );
    });

    test('the three FR-07 languages keep their BCP-47 codes', () {
      expect(ReplyLanguage.bengali.code, 'bn');
      expect(ReplyLanguage.hindi.code, 'hi');
      expect(ReplyLanguage.english.code, 'en');
    });

    test('unknown codes fall back instead of throwing', () {
      expect(ReplyLanguage.fromCode('kl'), ReplyLanguage.english);
      expect(ReplyTone.fromName('sarcastic'), ReplyTone.friendly);
      expect(ReplyLength.fromName(null), ReplyLength.short);
    });
  });

  test('only the two partner voices may write as a partner', () {
    // The gate is the whole safety of this feature: a register that quietly
    // became a persona would be the failure the prompt rules were written
    // for.
    final romantic = ReplyTone.values.where((tone) => tone.isRomantic);

    expect(romantic.map((tone) => tone.name), <String>['premika', 'premik']);
  });

  test('the wire shape carries the voice examples', () {
    // : the request JSON is the contract. Style examples
    // are prompt input, and an empty list is the normal state - not a field
    // that should go missing.
    const request = ReplyRequest(
      message: 'kal dekha hobe?',
      language: ReplyLanguage.bengali,
      tone: ReplyTone.casual,
      length: ReplyLength.short,
      styleExamples: ['aschi'],
      priorMessages: ['them: before this'],
    );

    final json = request.toJson();

    expect(json['styleExamples'], ['aschi']);
    expect(json['priorMessages'], ['them: before this']);
  });

  test('style examples default to empty', () {
    const request = ReplyRequest(
      message: 'hello',
      language: ReplyLanguage.english,
      tone: ReplyTone.friendly,
      length: ReplyLength.short,
    );

    expect(request.styleExamples, isEmpty);
    expect(request.toJson()['styleExamples'], isEmpty);
  });
}
