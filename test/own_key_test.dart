import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/own_key_reply_repository.dart';
import 'package:replymate/features/reply/data/own_key_store.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

ReplyRequest _request({String message = 'hello there'}) => ReplyRequest(
  message: message,
  language: ReplyLanguage.english,
  tone: ReplyTone.friendly,
  length: ReplyLength.short,
  count: 1,
);

void main() {
  setUpAll(() async {
    Hive.init('/tmp/replymate_own_key_test');
  });

  Future<Box<dynamic>> freshBox(String name) async {
    final box = Hive.isBoxOpen(name)
        ? Hive.box<dynamic>(name)
        : await Hive.openBox<dynamic>(name);
    await box.clear();
    return box;
  }

  group('OwnKeyStore', () {
    test(
      'a saved key comes back, and nothing is stored when none is set',
      () async {
        final store = OwnKeyStore(box: await freshBox('own_key_roundtrip'));
        expect(await store.read(), isNull);
        expect(store.hasKey, isFalse);

        await store.save(
          const OwnKey(
            key: 'sk-test-123',
            provider: 'openrouter',
            baseUrl: 'https://openrouter.ai/api/v1',
            model: 'openai/gpt-4o-mini',
          ),
        );

        expect(store.hasKey, isTrue);
        final restored = await store.read();
        expect(restored!.key, 'sk-test-123');
        expect(restored.provider, 'openrouter');
      },
    );

    test('clearing removes it', () async {
      final store = OwnKeyStore(box: await freshBox('own_key_clear'));
      await store.save(
        const OwnKey(
          key: 'sk-1',
          provider: 'openrouter',
          baseUrl: 'u',
          model: 'm',
        ),
      );
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('saving without a box fails loudly instead of pretending', () async {
      // The UI shows "Key saved on this device" only after this resolves, so a
      // store that cannot write must throw rather than quietly do nothing.
      final store = OwnKeyStore();
      expect(
        () => store.save(
          const OwnKey(
            key: 'sk-1',
            provider: 'openrouter',
            baseUrl: 'u',
            model: 'm',
          ),
        ),
        throwsStateError,
      );
    });

    test('a malformed entry reads as no key, never as a crash', () async {
      final box = await freshBox('own_key_malformed');
      await box.put('own_key', {'provider': 'openrouter'}); // no key field
      final store = OwnKeyStore(box: box);
      expect(await store.read(), isNull);
    });
  });

  group('OwnKeyReplyRepository', () {
    test('no key set is a clear, non-retryable failure', () async {
      final repo = OwnKeyReplyRepository(
        keys: OwnKeyStore(box: await freshBox('own_key_none')),
      );
      final result = await repo.generate(_request());
      expect(result, isA<ReplyFailure>());
      expect((result as ReplyFailure).isRetryable, isFalse);
      expect(result.message, contains('No personal API key'));
    });

    test('a 401 is reported as an auth failure, not a network one', () async {
      final box = await freshBox('own_key_401');
      await box.put('own_key', {
        'key': 'sk-bad',
        'provider': 'openrouter',
        'baseUrl': 'https://openrouter.ai/api/v1',
        'model': 'openai/gpt-4o-mini',
      });
      final repo = OwnKeyReplyRepository(
        keys: OwnKeyStore(box: box),
        httpClient: MockClient((_) async => http.Response('nope', 401)),
      );

      final result = await repo.generate(_request());
      expect(result, isA<ReplyFailure>());
      expect((result as ReplyFailure).message, contains('rejected'));
      // Retrying a rejected key just burns time.
      expect(result.isRetryable, isFalse);
    });

    test('a 200 is parsed into replies', () async {
      final box = await freshBox('own_key_200');
      await box.put('own_key', {
        'key': 'sk-good',
        'provider': 'openrouter',
        'baseUrl': 'https://openrouter.ai/api/v1',
        'model': 'openai/gpt-4o-mini',
      });
      final repo = OwnKeyReplyRepository(
        keys: OwnKeyStore(box: box),
        httpClient: MockClient((request) async {
          // The key goes in the Authorization header, and nowhere else.
          expect(request.headers['Authorization'], 'Bearer sk-good');
          expect(request.url.path, endsWith('/chat/completions'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['max_tokens'], isNotNull);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"replies": ["Sure thing."]}'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await repo.generate(_request());
      expect(result, isA<ReplySuccess>());
      expect((result as ReplySuccess).replies, ['Sure thing.']);
    });

    test('Gemini takes the generateContent path', () async {
      final box = await freshBox('own_key_gemini');
      await box.put('own_key', {
        'key': 'AIza-test',
        'provider': 'google',
        'baseUrl': 'https://generativelanguage.googleapis.com/v1beta',
        'model': 'gemini-2.0-flash',
      });
      final repo = OwnKeyReplyRepository(
        keys: OwnKeyStore(box: box),
        httpClient: MockClient((request) async {
          expect(request.url.path, contains(':generateContent'));
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"replies": ["ঠিক আছে"]}'},
                    ],
                  },
                },
              ],
            }),
            200,
            // Bengali in the body: without the charset, package:http decodes
            // as latin-1 and the reply arrives as mojibake.
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await repo.generate(_request());
      expect((result as ReplySuccess).replies, ['ঠিক আছে']);
    });

    test('provider defaults cover the three choices', () {
      expect(OwnKeyProvider.all.map((p) => p.id), contains('openrouter'));
      expect(OwnKeyProvider.all.map((p) => p.id), contains('google'));
      expect(OwnKeyProvider.byId('custom'), isNotNull);
      expect(OwnKeyProvider.byId('nope'), isNull);
    });
  });
}
