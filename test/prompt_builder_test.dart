import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/prompt_builder.dart';
import 'package:replymate/features/reply/domain/reply_intent.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';
import 'package:replymate/features/reply/domain/reply_refinement.dart';

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
    expect(system, contains('array of exactly 3 strings'));
    expect(system, contains('one valid JSON object and nothing else'));
    expect(system, contains('ready-to-send message'));
    expect(
      system,
      contains('Respect the requested language, tone and length exactly'),
    );
    expect(system, contains('native script'));
    expect(system, contains('{"replies":'));
  });

  test('JSON shape example matches the exact requested suggestion count', () {
    for (final count in [1, 2, 3]) {
      final system = ReplyPrompt.system(count, ReplyTone.friendly);
      expect(system, contains('array of exactly $count strings'));
      final shape =
          '{"replies": [${List<String>.generate(count, (index) => '"reply ${index + 1}"').join(', ')}]}';
      expect(system, contains(shape));
    }
  });

  test(
    'intent prompts give the selected direction without invented details',
    () {
      const intents = <ReplyIntent, String>{
        ReplyIntent.agree: 'agree to the request',
        ReplyIntent.politeDecline: 'decline this request politely',
        ReplyIntent.askForDetails: 'ask one concise question',
        ReplyIntent.suggestAnotherTime: 'invite another time',
      };
      for (final entry in intents.entries) {
        final prompt = ReplyPrompt.user(
          request.copyWith(replyIntent: entry.key),
        );
        expect(prompt, contains(entry.value));
      }
      final agree = ReplyPrompt.user(
        request.copyWith(replyIntent: ReplyIntent.agree),
      );
      expect(agree, contains('Do not add commitments, dates'));
      final anotherTime = ReplyPrompt.user(
        request.copyWith(replyIntent: ReplyIntent.suggestAnotherTime),
      );
      expect(anotherTime, contains('Do not invent a specific date or time'));
    },
  );

  test('ambiguous input is not treated as permission to agree or commit', () {
    final system = ReplyPrompt.system(1, ReplyTone.friendly);
    expect(system, contains('If the message is ambiguous'));
    expect(system, contains('ask a clarifying question instead'));
  });

  test(
    'standalone mode treats the text as a writing brief, not a chat to answer',
    () {
      const request = ReplyRequest(
        message: 'Write a tiny romantic quote for my girlfriend in Bengali.',
        language: ReplyLanguage.english,
        tone: ReplyTone.friendly,
        length: ReplyLength.short,
        count: 2,
        mode: ReplyMode.createMessage,
      );
      final system = ReplyPrompt.system(
        2,
        ReplyTone.friendly,
        mode: ReplyMode.createMessage,
      );
      final user = ReplyPrompt.user(request);

      expect(system, contains('standalone writing request'));
      expect(
        system,
        contains('Follow explicit language, tone and length instructions'),
      );
      expect(
        system,
        isNot(
          contains('Preserve the intended meaning of the incoming message'),
        ),
      );
      expect(system, isNot(contains('If the message is ambiguous')));
      expect(system, isNot(contains('Do not assume a relationship')));
      expect(user, contains('Your writing request:'));
      expect(user, contains('Create 2 original message suggestion(s)'));
      expect(
        user,
        contains('unless the request explicitly asks for another language'),
      );
      expect(user, isNot(contains('Incoming message:')));
      final rewrite = ReplyPrompt.user(
        request.copyWith(
          draftToRefine: 'তুমি আমার দিনের আলো।',
          refinementInstruction: 'Make it even shorter.',
        ),
      );
      expect(rewrite, contains('Original writing request (context only):'));
      expect(rewrite, isNot(contains('Original incoming message')));
    },
  );

  test('standalone follow-ups include earlier chat turns as context', () {
    const request = ReplyRequest(
      message: 'Make it more playful.',
      language: ReplyLanguage.english,
      tone: ReplyTone.friendly,
      length: ReplyLength.short,
      count: 2,
      mode: ReplyMode.createMessage,
      priorMessages: [
        'User: Write a birthday message.',
        'Assistant: Happy birthday! Hope your day is lovely.',
      ],
    );

    final prompt = ReplyPrompt.user(request);

    expect(prompt, contains('Earlier in this conversation:'));
    expect(prompt, contains('- User: Write a birthday message.'));
    expect(prompt, contains('- Assistant: Happy birthday!'));
    expect(prompt, contains('Your writing request:\nMake it more playful.'));
  });

  test('the user prompt carries message, language, tone and length', () {
    final user = ReplyPrompt.user(request);
    expect(user, contains('Can we meet tomorrow?'));
    expect(user, contains('Bengali'));
    expect(user, contains('Professional'));
    expect(user, contains('Short'));
    expect(user, contains('3 reply suggestion(s)'));
  });

  test('a rewrite prompt preserves the draft and requested transformation', () {
    const base = ReplyRequest(
      message: 'Can we meet tomorrow?',
      language: ReplyLanguage.bengali,
      tone: ReplyTone.polite,
      length: ReplyLength.short,
    );
    final rewrite = base.copyWith(
      count: 1,
      draftToRefine: 'হ্যাঁ, আমি আসব।',
      refinementInstruction:
          'Rewrite as a polite decline without inventing a reason.',
    );
    final user = ReplyPrompt.user(rewrite);

    expect(user, contains('Can we meet tomorrow?'));
    expect(user, contains('হ্যাঁ, আমি আসব।'));
    expect(user, contains('polite decline'));
    expect(user, contains('exactly one revised reply'));
    expect(user, isNot(contains('Write 1 reply suggestion(s)')));
  });

  test('continuation prompt asks at most one grounded follow-up question', () {
    const base = ReplyRequest(
      message: 'Can we meet tomorrow?',
      language: ReplyLanguage.bengali,
      tone: ReplyTone.casual,
      length: ReplyLength.medium,
      priorMessages: ['Friend: Friday works for me.'],
    );
    final rewrite = base.copyWith(
      count: 1,
      draftToRefine: 'হ্যাঁ, দেখা হবে।',
      refinementInstruction: ReplyRefinement.continueConversation.instruction,
    );
    final user = ReplyPrompt.user(rewrite);

    expect(user, contains('Friend: Friday works for me.'));
    expect(user, contains('হ্যাঁ, দেখা হবে।'));
    expect(user, contains('at most one concise, relevant question'));
    expect(user, contains('return the original draft unchanged'));
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
    expect(system, contains('array of exactly 2 strings'));
    expect(system, contains('{"replies":'));
  });

  group('voice examples', () {
    test('an empty list adds nothing at all', () {
      final system = ReplyPrompt.system(1, ReplyTone.friendly);

      // With memory off (or nothing to learn from) the prompt must be exactly
      // what it always was - no empty scaffold, no dangling header.
      expect(system, isNot(contains('How this user writes')));
    });

    test('the user\'s own lines are quoted back as examples', () {
      final system = ReplyPrompt.system(
        1,
        ReplyTone.casual,
        styleExamples: ['haa aschi, ektu deri hobe', 'kal dekha hobe tahole'],
      );

      expect(system, contains('How this user writes'));
      expect(system, contains('- haa aschi, ektu deri hobe'));
      expect(system, contains('- kal dekha hobe tahole'));
    });

    test('the examples are fenced as things not to answer', () {
      // A model handed stray lines replies to them: that would produce a draft
      // answering the user's own sentence instead of the incoming message.
      final system = ReplyPrompt.system(
        1,
        ReplyTone.friendly,
        styleExamples: ['aschi'],
      );

      expect(system, contains('do not reply to'));
      expect(system, contains('do not repeat their content'));
      // The examples are in the system prompt; the message being answered is
      // still the only thing framed as incoming.
      expect(system, isNot(contains('Incoming message')));
    });

    test('the rest of the rules survive the extra block', () {
      final system = ReplyPrompt.system(
        3,
        ReplyTone.professional,
        styleExamples: ['aschi'],
      );

      expect(system, contains('Preserve the intended meaning'));
      expect(system, contains('array of exactly 3 strings'));
      expect(system, contains('Do not assume a relationship'));
    });
  });
}
