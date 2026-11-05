import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

void main() {
  const repository = NotConfiguredReplyRepository();

  ReplyRequest request({String message = 'Can we meet tomorrow?'}) =>
      ReplyRequest(
        message: message,
        language: ReplyLanguage.english,
        tone: ReplyTone.polite,
        length: ReplyLength.short,
      );

  test('batch 1 never fabricates a reply (docs/AI_INTEGRATION.md)', () async {
    final result = await repository.generate(request());
    expect(result, isA<ReplyFailure>());
    final failure = result as ReplyFailure;
    expect(failure.message, contains('not configured'));
    expect(failure.isRetryable, isFalse);
  });

  test('validation problems are reported before any backend talk', () async {
    final result = await repository.generate(request(message: '   '));
    expect(result, isA<ReplyFailure>());
    expect((result as ReplyFailure).message, contains('paste the text'));
  });

  test('success and failure are distinguishable by pattern', () {
    const ReplyResult success = ReplySuccess(['Sure!']);
    const ReplyResult failure = ReplyFailure('nope');
    expect(success, isA<ReplySuccess>());
    expect((success as ReplySuccess).replies, ['Sure!']);
    expect(failure, isA<ReplyFailure>());
  });
}
