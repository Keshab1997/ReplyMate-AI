import 'dart:convert';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replymate/features/reply/data/openai_client.dart';

AdminApiKey key() => AdminApiKey(
  id: 'k1',
  name: 'test',
  key: 'sk-test',
  baseUrl: 'https://provider.example/v1',
  model: 'test-model',
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
}
