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
import 'package:replymate/features/reply/domain/writing_format.dart';

class FakeKeySource implements KeySource {
  FakeKeySource(this._key) : _queue = null;

  /// Hands out [keys] in order, then null - the shape a real pool has when its
  /// first key is on cooldown and the next one is free.
  FakeKeySource.queue(List<AdminApiKey> keys)
    : _key = null,
      _queue = List<AdminApiKey>.of(keys);

  final AdminApiKey? _key;
  final List<AdminApiKey>? _queue;
  final List<int> reportedFailures = [];
  final List<String> reportedKeyIds = [];
  int ensureReadyCalls = 0;
  int successes = 0;
  int nextCalls = 0;

  @override
  Future<void> ensureReady() async {
    ensureReadyCalls++;
  }

  @override
  AdminApiKey? next() {
    nextCalls++;
    final queue = _queue;
    if (queue == null) return _key;
    return queue.isEmpty ? null : queue.removeAt(0);
  }

  @override
  void reportSuccess(AdminApiKey key) => successes++;

  @override
  void reportFailure(AdminApiKey key, int statusCode) {
    reportedFailures.add(statusCode);
    reportedKeyIds.add(key.id);
  }
}

AdminApiKey key({String id = 'k1', String provider = 'custom'}) => AdminApiKey(
  id: id,
  name: 'test',
  key: 'sk-test',
  baseUrl: 'https://provider.example/v1',
  model: 'm',
  provider: provider,
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

  test('an empty answer reports the key and tries the next one', () async {
    // The user-facing bug: one provider returning `{"replies": []}` made every
    // tap fail forever, because the key was never taken out of rotation.
    final keys = FakeKeySource.queue([key(), key(id: 'k2')]);
    var calls = 0;
    final repository = KeyPoolReplyRepository(
      keys: keys,
      client: OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          calls++;
          final content = calls == 1
              ? '{"replies": []}'
              : '{"replies": ["দ্বিতীয় কী থেকে"]}';
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': content},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.generate(request());
    expect(result, isA<ReplySuccess>());
    expect((result as ReplySuccess).replies, ['দ্বিতীয় কী থেকে']);
    expect(keys.reportedKeyIds, ['k1']);
    expect(calls, 2);
  });

  test(
    'a dead pool reports the honest failure after all keys are tried',
    () async {
      final keys = FakeKeySource.queue([
        key(),
        key(id: 'k2'),
        key(id: 'k3'),
        key(id: 'k4'),
      ]);
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
      // Bounded: three attempts, never the whole pool.
      expect(keys.reportedKeyIds, ['k1', 'k2', 'k3']);
      expect(keys.nextCalls, 3);
    },
  );

  test('a one-key pool is not retried against itself', () async {
    // The fake hands the same key back forever, which a pool whose only key is
    // cooling down effectively does. One provider call, then stop: the second
    // `next()` is the probe that discovers there is nothing else to try.
    final keys = FakeKeySource(key());
    var calls = 0;
    final repository = KeyPoolReplyRepository(
      keys: keys,
      client: OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"replies": []}'},
                },
              ],
            }),
            200,
          );
        }),
      ),
    );
    final result = await repository.generate(request());
    expect(result, isA<ReplyFailure>());
    expect(calls, 1);
    expect(keys.reportedKeyIds, ['k1']);
  });

  test('a rejected key stops the loop instead of burning the pool', () async {
    final keys = FakeKeySource.queue([key(), key(id: 'k2')]);
    final repository = repositoryWith(keys, 401, '{}');
    final result = await repository.generate(request());
    expect(result, isA<ReplyFailure>());
    expect((result as ReplyFailure).isRetryable, isFalse);
    expect(keys.reportedKeyIds, ['k1']);
  });

  test('a rate-limited key is followed by the next healthy one', () async {
    final keys = FakeKeySource.queue([key(), key(id: 'k2')]);
    var calls = 0;
    final repository = KeyPoolReplyRepository(
      keys: keys,
      client: OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          calls++;
          if (calls == 1) return http.Response('{}', 429);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"replies": ["ok then"]}'},
                },
              ],
            }),
            200,
          );
        }),
      ),
    );
    final result = await repository.generate(request());
    expect(result, isA<ReplySuccess>());
    expect(keys.reportedKeyIds, ['k1']);
    expect(keys.successes, 1);
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

  test('parseReplies unwraps fenced and double-encoded JSON', () {
    expect(
      KeyPoolReplyRepository.parseReplies(
        '```json\n{"replies":["ঠিক আছে"]}\n```',
        2,
      ),
      ['ঠিক আছে'],
    );
    expect(
      KeyPoolReplyRepository.parseReplies(
        jsonEncode('{"replies":["আচ্ছা, বলো কী হয়েছে?"]}'),
        2,
      ),
      ['আচ্ছা, বলো কী হয়েছে?'],
    );
  });

  test('parseReplies extracts JSON wrapped in brief provider prose', () {
    expect(
      KeyPoolReplyRepository.parseReplies(
        'Here are the suggestions: {"replies":["Sure, that works."]}',
        2,
      ),
      ['Sure, that works.'],
    );
  });

  test(
    'parseReplies salvages replies from truncated JSON, not its wrapper',
    () {
      const malformed =
          '{"replies": ["এই তো, কী হয়েছে বলো?", "বলতে চাইলে আমি শুনছি."';
      expect(KeyPoolReplyRepository.parseReplies(malformed, 2), [
        'এই তো, কী হয়েছে বলো?',
        'বলতে চাইলে আমি শুনছি.',
      ]);
      expect(
        KeyPoolReplyRepository.parseReplies('{"replies": [broken', 2),
        isEmpty,
      );
    },
  );

  test('plain-text fallback strips list numbering', () {
    expect(
      KeyPoolReplyRepository.parseReplies('1. Sure.\n2) Sounds good.', 2),
      ['Sure.', 'Sounds good.'],
    );
  });

  test(
    'parseReplies strips <think> blocks including braces before parsing',
    () {
      const raw =
          '<think>Format should be {"replies": ["reply 1"]}. Thinking...</think>\n'
          '{"replies": ["হ্যাঁ, কাল দেখা হবে।"]}';
      expect(KeyPoolReplyRepository.parseReplies(raw, 1), [
        'হ্যাঁ, কাল দেখা হবে।',
      ]);
    },
  );

  test('parseReplies returns empty when response is only unclosed <think>', () {
    expect(
      KeyPoolReplyRepository.parseReplies(
        '<think>Let me think about how to answer this...',
        1,
      ),
      isEmpty,
    );
  });

  test('parseReplies recovers JSON strings with raw unescaped newlines', () {
    const raw =
        '{"replies": ["Subject: Leave request\n\nDear Sir,\nPlease grant me leave."]}';
    expect(KeyPoolReplyRepository.parseReplies(raw, 1), [
      'Subject: Leave request\n\nDear Sir,\nPlease grant me leave.',
    ]);
  });

  test(
    'awaits key pool readiness and forwards document format to prompt',
    () async {
      final keys = FakeKeySource(key());
      String? systemPrompt;
      final repository = KeyPoolReplyRepository(
        keys: keys,
        client: OpenAiCompatibleClient(
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            systemPrompt =
                (body['messages'] as List).first['content'] as String;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '{"replies": ["To, The Principal..."]}',
                    },
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );

      final result = await repository.generate(
        const ReplyRequest(
          message: 'Leave application for fever.',
          language: ReplyLanguage.english,
          tone: ReplyTone.professional,
          length: ReplyLength.medium,
          count: 1,
          mode: ReplyMode.createMessage,
          format: WritingFormat.application,
        ),
      );
      expect(result, isA<ReplySuccess>());
      expect(keys.ensureReadyCalls, 1);
      expect(systemPrompt, contains('recipient block'));
    },
  );
}
