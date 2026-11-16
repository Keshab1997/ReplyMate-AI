import 'dart:convert';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replymate/features/reply/data/openai_client.dart';

AdminApiKey key({
  String baseUrl = 'https://provider.example/v1',
  String model = 'test-model',
  String provider = 'custom',
}) => AdminApiKey(
  id: 'k1',
  name: 'test',
  key: 'sk-test',
  baseUrl: baseUrl,
  model: model,
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

OpenAiCompatibleClient clientReturning(
  int status,
  String body, {
  void Function(http.Request request)? onRequest,
}) => OpenAiCompatibleClient(
  httpClient: MockClient((request) async {
    onRequest?.call(request);
    return http.Response(body, status);
  }),
);

void main() {
  test('posts to /chat/completions with the bearer key and model', () async {
    http.Request? seen;
    final client = clientReturning(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': '{"replies": ["hi"]}'},
          },
        ],
      }),
      onRequest: (request) => seen = request,
    );
    await client.complete(key: key(), systemPrompt: 'sys', userPrompt: 'usr');
    expect(
      seen!.url.toString(),
      'https://provider.example/v1/chat/completions',
    );
    expect(seen!.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode(seen!.body) as Map<String, Object?>;
    expect(body['model'], 'test-model');
    expect((body['messages'] as List).first['role'], 'system');
  });

  test('200 with a content payload returns the raw content', () async {
    final client = clientReturning(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': '{"replies": ["a", "b"]}'},
          },
        ],
      }),
    );
    final content = await client.complete(
      key: key(),
      systemPrompt: 's',
      userPrompt: 'u',
    );
    expect(content, '{"replies": ["a", "b"]}');
  });

  test('401 and 403 are auth failures, never retryable', () async {
    for (final status in [401, 403]) {
      final client = clientReturning(status, '{}');
      await expectLater(
        client.complete(key: key(), systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<AuthFailure>()),
      );
    }
  });

  test('429 is a retryable rate limit', () async {
    final client = clientReturning(429, '{}');
    await expectLater(
      client.complete(key: key(), systemPrompt: 's', userPrompt: 'u'),
      throwsA(isA<RateLimited>()),
    );
  });

  test('5xx is a retryable server error carrying the status', () async {
    final client = clientReturning(503, '{}');
    try {
      await client.complete(key: key(), systemPrompt: 's', userPrompt: 'u');
      fail('expected ServerError');
    } on ServerError catch (error) {
      expect(error.statusCode, 503);
      expect(error.isRetryable, isTrue);
    }
  });

  test('200 with an unreadable body is malformed, not success', () async {
    for (final body in ['not json', '{"choices": []}', '{"choices": [{}]}']) {
      final client = clientReturning(200, body);
      await expectLater(
        client.complete(key: key(), systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<MalformedResponse>()),
      );
    }
  });

  test('a bare model on OpenRouter is prefixed the way OpenRouter wants it', () async {
    // The admin health check already does this mapping; the real call used to
    // send `gpt-4o-mini` and take a 400 from OpenRouter while the admin screen
    // showed a healthy key.
    http.Request? seen;
    final client = clientReturning(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': '{"replies": ["hi"]}'},
          },
        ],
      }),
      onRequest: (request) => seen = request,
    );
    await client.complete(
      key: key(baseUrl: 'https://openrouter.ai/api/v1', model: 'gpt-4o-mini'),
      systemPrompt: 's',
      userPrompt: 'u',
    );
    final body = jsonDecode(seen!.body) as Map<String, Object?>;
    expect(body['model'], 'openai/gpt-4o-mini');
  });

  test(
    'an already-prefixed OpenRouter model is left exactly as entered',
    () async {
      http.Request? seen;
      final client = clientReturning(
        200,
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"replies": ["hi"]}'},
            },
          ],
        }),
        onRequest: (request) => seen = request,
      );
      await client.complete(
        key: key(
          baseUrl: 'https://openrouter.ai/api/v1',
          model: 'openai/gpt-4o-mini',
        ),
        systemPrompt: 's',
        userPrompt: 'u',
      );
      expect((jsonDecode(seen!.body) as Map)['model'], 'openai/gpt-4o-mini');
    },
  );

  test(
    'a google provider key uses generateContent, not /chat/completions',
    () async {
      http.Request? seen;
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"replies": ["hi"]}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final content = await client.complete(
        key: key(
          provider: 'google',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          model: 'gemini-2.0-flash',
        ),
        systemPrompt: 'sys',
        userPrompt: 'usr',
      );
      expect(
        seen!.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent?key=sk-test',
      );
      expect(content, '{"replies": ["hi"]}');
      final body = jsonDecode(seen!.body) as Map;
      expect((body['contents'] as List).first['role'], 'user');
      expect(body['generationConfig']['responseMimeType'], 'application/json');
    },
  );

  test(
    'a google key with an empty candidate list is malformed, not success',
    () async {
      final client = OpenAiCompatibleClient(
        httpClient: MockClient(
          (request) async => http.Response('{"candidates": []}', 200),
        ),
      );
      await expectLater(
        client.complete(
          key: key(provider: 'google'),
          systemPrompt: 's',
          userPrompt: 'u',
        ),
        throwsA(isA<MalformedResponse>()),
      );
    },
  );

  test('a google key 429 is still a retryable rate limit', () async {
    final client = OpenAiCompatibleClient(
      httpClient: MockClient((request) async => http.Response('{}', 429)),
    );
    await expectLater(
      client.complete(
        key: key(provider: 'google'),
        systemPrompt: 's',
        userPrompt: 'u',
      ),
      throwsA(isA<RateLimited>()),
    );
  });

  test(
    'a connection failure becomes a retryable server error with code 0',
    () async {
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async => throw Exception('dns boom')),
      );
      try {
        await client.complete(key: key(), systemPrompt: 's', userPrompt: 'u');
        fail('expected ServerError');
      } on ServerError catch (error) {
        expect(error.statusCode, 0);
        expect(error.isRetryable, isTrue);
      }
    },
  );

  test(
    'reasoning model exhausting max_tokens retries once with expanded budget',
    () async {
      final seenBodies = <Map<String, Object?>>[];
      var calls = 0;
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          calls++;
          seenBodies.add(jsonDecode(request.body) as Map<String, Object?>);
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'length',
                    'message': {
                      'content': null,
                      'reasoning': 'Thinking about the Bengali reply...',
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': '{"replies": ["হ্যাঁ, নিশ্চয়ই।"]}'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final content = await client.complete(
        key: key(),
        systemPrompt: 'sys',
        userPrompt: 'usr',
        maxOutputTokens: 300,
      );
      expect(calls, 2);
      expect(seenBodies[0]['max_tokens'], 300);
      expect(seenBodies[1]['max_tokens'], 2048);
      expect(content, '{"replies": ["হ্যাঁ, নিশ্চয়ই।"]}');
    },
  );

  test('400 from system role or temperature falls back to ping-compatible user shape', () async {
    final seenBodies = <Map<String, Object?>>[];
    var calls = 0;
    final client = OpenAiCompatibleClient(
      httpClient: MockClient((request) async {
        calls++;
        seenBodies.add(jsonDecode(request.body) as Map<String, Object?>);
        if (calls == 1) {
          return http.Response(
            '{"error": {"message": "Developer instruction is not enabled"}}',
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"replies": ["Sure!"]}'},
              },
            ],
          }),
          200,
        );
      }),
    );

    final content = await client.complete(
      key: key(baseUrl: 'https://openrouter.ai/api/v1/'),
      systemPrompt: 'sys rules',
      userPrompt: 'usr prompt',
    );
    expect(calls, 2);
    expect(seenBodies[1].containsKey('temperature'), isFalse);
    final messages = seenBodies[1]['messages'] as List;
    expect(messages, hasLength(1));
    expect((messages.first as Map)['role'], 'user');
    expect((messages.first as Map)['content'], 'sys rules\n\nusr prompt');
    expect(content, '{"replies": ["Sure!"]}');
  });

  test('openAI content part lists skip thinking parts and join text', () async {
    final client = clientReturning(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': [
                {'type': 'thinking', 'text': 'internal'},
                {'type': 'text', 'text': '{"replies": ["ok"]}'},
              ],
            },
          },
        ],
      }),
    );
    final content = await client.complete(
      key: key(),
      systemPrompt: 's',
      userPrompt: 'u',
    );
    expect(content, '{"replies": ["ok"]}');
  });

  test(
    'google 2.5 thinking parts are skipped and budget keeps room for thinking',
    () async {
      http.Request? seen;
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'Let me think {not json}'},
                      {'text': '{"replies": ["ভালো আছি।"]}'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final content = await client.complete(
        key: key(
          provider: 'google',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta/',
          model: 'gemini-2.5-flash',
        ),
        systemPrompt: 'sys',
        userPrompt: 'usr',
        maxOutputTokens: 300,
      );
      final body = jsonDecode(seen!.body) as Map;
      expect(
        body['generationConfig']['maxOutputTokens'],
        greaterThanOrEqualTo(2048),
      );
      expect(seen!.url.toString(), isNot(contains('//models')));
      expect(content, '{"replies": ["ভালো আছি।"]}');
    },
  );

  test(
    'google MAX_TOKENS empty response retries with 4096 output tokens',
    () async {
      final budgets = <int>[];
      var calls = 0;
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map;
          budgets.add(body['generationConfig']['maxOutputTokens'] as int);
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'MAX_TOKENS',
                    'content': {'role': 'model'},
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': '{"replies": ["Done"]}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final content = await client.complete(
        key: key(
          provider: 'google',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          model: 'gemini-2.5-pro',
        ),
        systemPrompt: 'sys',
        userPrompt: 'usr',
        maxOutputTokens: 300,
      );
      expect(calls, 2);
      expect(budgets, [2048, 4096]);
      expect(content, '{"replies": ["Done"]}');
    },
  );

  test(
    'gemma on google AI studio skips systemInstruction and responseSchema',
    () async {
      http.Request? seen;
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"replies": ["Hi there!"]}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final content = await client.complete(
        key: key(
          provider: 'google',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          model: 'gemma-3-27b-it',
        ),
        systemPrompt: 'sys',
        userPrompt: 'usr',
      );
      final body = jsonDecode(seen!.body) as Map;
      expect(body.containsKey('systemInstruction'), isFalse);
      expect(
        (body['generationConfig'] as Map).containsKey('responseSchema'),
        isFalse,
      );
      expect(
        (body['contents'] as List).first['parts'][0]['text'],
        'sys\n\nusr',
      );
      expect(content, '{"replies": ["Hi there!"]}');
    },
  );

  test(
    'google 400 on structured config falls back to plain generateContent',
    () async {
      var calls = 0;
      final client = OpenAiCompatibleClient(
        httpClient: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              '{"error": {"message": "JSON mode is not enabled"}}',
              400,
            );
          }
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"replies": ["Fallback ok"]}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final content = await client.complete(
        key: key(
          provider: 'google',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          model: 'custom-google-model',
        ),
        systemPrompt: 'sys',
        userPrompt: 'usr',
      );
      expect(calls, 2);
      expect(content, '{"replies": ["Fallback ok"]}');
    },
  );
}
