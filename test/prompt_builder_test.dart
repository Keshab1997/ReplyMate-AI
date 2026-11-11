import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/prompt_builder.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

void main() {
  const request = ReplyRequest(
    message: 'Can we meet tomorrow?',
    language: ReplyLanguage.bengali,
    tone: ReplyTone.professional,
    length: ReplyLength.short,
    count: 3,
  );

  test('the system prompt carries the documented prompt rules', () {
    final system = ReplyPrompt.system(3, ReplyTone.professional);
    expect(system, contains('Preserve the intended meaning'));
    expect(system, contains('Do not invent facts'));
    expect(system, contains('exactly 3 replies'));
    expect(system, contains('{"replies":'));
  });

  test('the user prompt carries message, language, tone and length', () {
    final user = ReplyPrompt.user(request);
    expect(user, contains('Can we meet tomorrow?'));
    expect(user, contains('Bengali'));
    expect(user, contains('Professional'));
    expect(user, contains('Short'));
    expect(user, contains('3 reply suggestion(s)'));
  });

  test('the message is trimmed before it reaches the provider', () {
    const padded = ReplyRequest(
      message: '  hello  ',
      language: ReplyLanguage.english,
      tone: ReplyTone.casual,
      length: ReplyLength.medium,
    );
    expect(ReplyPrompt.user(padded), contains('hello\n'));
    expect(ReplyPrompt.user(padded), isNot(contains('  hello  ')));
  });

  test('an ordinary tone still refuses to assume a relationship', () {
    // The rule has not been relaxed behind the user's back: it is lifted only
    // for the two voices whose whole point is being asked for.
    for (final tone in <ReplyTone>[
      ReplyTone.friendly,
      ReplyTone.casual,
      ReplyTone.professional,
      ReplyTone.polite,
      ReplyTone.funny,
      ReplyTone.shortAndDirect,
    ]) {
      final system = ReplyPrompt.system(1, tone);
      expect(system, contains('Do not assume a relationship'), reason: '$tone');
      expect(system, isNot(contains('Voice for this reply')));
    }
  });

  test('the partner voices say who is writing', () {
    final premika = ReplyPrompt.system(1, ReplyTone.premika);
    final premik = ReplyPrompt.system(1, ReplyTone.premik);

    expect(premika, contains('a girlfriend writing to the man she loves'));
    expect(premik, contains('a boyfriend writing to the woman he loves'));
  });

  test('the partner voices are told to use তুমি, not আপনি', () {
    // The whole point of the voice, and the thing a model left to itself gets
    // wrong: আপনি is what you write to a stranger.
    for (final tone in <ReplyTone>[ReplyTone.premika, ReplyTone.premik]) {
      final system = ReplyPrompt.system(1, tone);
      expect(system, contains('তুমি'), reason: '$tone');
      expect(system, contains('আপনি'), reason: '$tone');
      expect(system, contains('तुम'), reason: '$tone');
    }
  });

  test('the partner voices cap the emojis and forbid invented memories', () {
    final system = ReplyPrompt.system(1, ReplyTone.premika);

    // A row of emojis is what gives a generated reply away.
    expect(system, contains('One or two love emojis at the most'));
    // Warmth is allowed; making up a first meeting is not.
    expect(system, contains('no memories or plans you were not told'));
    expect(system, contains('Invent no shared history'));
  });

  test('a partner voice does not drop the rest of the rules', () {
    final system = ReplyPrompt.system(2, ReplyTone.premik);

    expect(system, contains('Preserve the intended meaning'));
    expect(system, contains('Do not invent facts'));
    expect(system, contains('exactly 2 replies'));
    expect(system, contains('{"replies":'));
  });
}
