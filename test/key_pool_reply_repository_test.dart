import 'dart:convert';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/key_pool_reply_repository.dart';
import 'package:replymate/features/reply/data/key_source.dart';
import 'package:replymate/features/reply/data/openai_client.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

class FakeKeySource implements KeySource {
  FakeKeySource(this._key);

  final AdminApiKey? _key;
  final List<int> reportedFailures = [];
  int successes = 0;

  @override
  AdminApiKey? next() => _key;

  @override
  void reportSuccess(AdminApiKey key) => successes++;

  @override
  void reportFailure(AdminApiKey key, int statusCode) =>
      reportedFailures.add(statusCode);
}

AdminApiKey key() => AdminApiKey(
  id: 'k1',
  name: 'test',
  key: 'sk-test',
  baseUrl: 'https://provider.example/v1',
  model: 'm',
  provider: 'custom',
  isActive: true,
  priority: 1,
  usageCount: 0,
  errorCount: 0,
  lastErrorAt: null,
  lastUsedAt: null,
  addedBy: 'test',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ReplyRequest request() => const ReplyRequest(
  message: 'Can we meet tomorrow?',
  language: ReplyLanguage.bengali,
  tone: ReplyTone.friendly,
  length: ReplyLength.short,
  count: 2,
);

KeyPoolReplyRepository repositoryWith(
  FakeKeySource keys,
  int status,
  String body,
) => KeyPoolReplyRepository(
  keys: keys,
  client: OpenAiCompatibleClient(
    httpClient: MockClient((request) async => http.Response(body, status)),
  ),
);

/// Same, but the mock response carries the charset a real provider sends, so
/// non-ASCII suggestion text survives the mock's own body encoding.
KeyPoolReplyRepository repositoryWithUtf8(
  FakeKeySource keys,
  int status,
  String body,
) => KeyPoolReplyRepository(
  keys: keys,
  client: OpenAiCompatibleClient(
    httpClient: MockClient(
      (request) async => http.Response(
        body,
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  ),
);

void main() {
  test('an empty pool is an honest retryable failure, not a crash', () async {
    final keys = FakeKeySource(null);
    final repository = repositoryWith(keys, 200, '{}');
    final result = await repository.generate(request());
    expect(result, isA<ReplyFailure>());
    expect((result as ReplyFailure).message, contains('key pool'));
    expect(result.isRetryable, isTrue);
    expect(keys.reportedFailures, isEmpty);
  });

  test('a JSON reply list becomes suggestions and reports success', () async {
    final keys = FakeKeySource(key());
    final repository = repositoryWithUtf8(
      keys,
      200,
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': jsonEncode({
                'replies': ['আচ্ছা, কাল বিকেল ৪টা?', 'হ্যাঁ, কাল দেখা হবে।'],
              }),
            },
          },
        ],
      }),
    );
    final result = await repository.generate(request());
    expect(result, isA<ReplySuccess>());
    expect((result as ReplySuccess).replies, hasLength(2));
    expect(keys.successes, 1);
  });

  test('a provider that ignores the JSON shape falls back to lines', () async {
    final keys = FakeKeySource(key());
    final repository = repositoryWith(
      keys,
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': 'Sure!\nYes, tomorrow works.'},
          },
        ],
      }),
    );
    final result = await repository.generate(request());
    expect((result as ReplySuccess).replies, ['Sure!', 'Yes, tomorrow works.']);
  });

  test('rate limits are reported to the pool and stay retryable', () async {
    final keys = FakeKeySource(key());
    final repository = repositoryWith(keys, 429, '{}');
    final result = await repository.generate(request());
    expect((result as ReplyFailure).isRetryable, isTrue);
    expect(keys.reportedFailures, [429]);
  });

  test('auth failures are reported and never retried blindly', () async {
    final keys = FakeKeySource(key());
    final repository = repositoryWith(keys, 401, '{}');
    final result = await repository.generate(request());
    expect((result as ReplyFailure).isRetryable, isFalse);
    expect(keys.reportedFailures, [401]);
  });

  test('an empty suggestion list is a failure, not a silent success', () async {
    final keys = FakeKeySource(key());
    final repository = repositoryWith(
      keys,
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': '{"replies": []}'},
          },
        ],
      }),
    );
    final result = await repository.generate(request());
    expect(result, isA<ReplyFailure>());
    expect((result as ReplyFailure).message, contains('empty'));
  });

  test('parseReplies trims, drops blanks and respects count', () {
    expect(KeyPoolReplyRepository.parseReplies('  a  \n\n b \n c ', 2), [
      'a',
      'b',
    ]);
  });
}
