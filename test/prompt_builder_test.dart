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
    final system = ReplyPrompt.system(3);
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
}
