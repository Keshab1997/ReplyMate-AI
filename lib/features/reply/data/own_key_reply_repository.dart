import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/reply_request.dart';
import 'key_pool_reply_repository.dart';
import 'openai_client.dart';
import 'own_key_store.dart';
import 'prompt_builder.dart';
import 'reply_repository.dart';

/// Generates replies with the user's **own** key, held on this device.
///
/// This is the security answer that fits a no-billing app. A key in the user's
/// Hive box cannot be read out of Firestore, has no rules to get wrong, and
/// burns nobody else's quota. It also means the app works with no Firebase
/// project at all — today a missing `google-services.json` means no AI.
///
/// It is deliberately a second small repository rather than a branch inside
/// [KeyPoolReplyRepository]: the pool path has failover, cooldowns and health
/// checks it does not need, and entangling them is how the pool path gets
/// broken by a change meant for this one.
class OwnKeyReplyRepository implements ReplyRepository {
  OwnKeyReplyRepository({required this.keys, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final OwnKeyStore keys;
  final http.Client _http;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      return ReplyFailure(problems.join(' '), isRetryable: false);
    }

    final key = await keys.read();
    if (key == null || key.key.trim().isEmpty) {
      return const ReplyFailure(
        'No personal API key is set. Add one in Settings → Your own AI key, '
        'or use the offline suggestions.',
        isRetryable: false,
      );
    }

    try {
      final content = await _call(
        key: key,
        systemPrompt: ReplyPrompt.system(
          request.count,
          request.tone,
          styleExamples: request.styleExamples,
        ),
        userPrompt: ReplyPrompt.user(request),
      );
      final replies = KeyPoolReplyRepository.parseReplies(
        content,
        request.count,
      );
      if (replies.isEmpty) {
        return const ReplyFailure(
          'Your provider returned no suggestions.',
          isRetryable: true,
        );
      }
      return ReplySuccess(replies);
    } on AiCallException catch (error) {
      return ReplyFailure(error.userMessage, isRetryable: error.isRetryable);
    } catch (_) {
      return const ReplyFailure(
        'Network problem while reaching your provider.',
        isRetryable: true,
      );
    }
  }

  Future<String> _call({
    required OwnKey key,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (key.provider == 'google') {
      return _callGemini(
        key: key,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
    }

    final uri = Uri.parse('${key.baseUrl}/chat/completions');
    final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${key.key}',
            },
            body: jsonEncode({
              'model': key.model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              'temperature': 0.7,
              'max_tokens': OpenAiCompatibleClient.maxTokens,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const ServerError(0);
    }
    switch (response.statusCode) {
      case 200:
        return OpenAiCompatibleClient.extractContent(
          utf8.decode(response.bodyBytes),
        );
      case 401:
      case 403:
        throw AuthFailure(response.statusCode);
      case 429:
        throw const RateLimited();
      default:
        throw ServerError(response.statusCode);
    }
  }

  /// Gemini speaks its own shape. Kept here rather than in a client class
  /// because it is three lines of JSON and an abstraction for it would be
  /// larger than the thing it hides.
  Future<String> _callGemini({
    required OwnKey key,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final uri = Uri.parse(
      '${key.baseUrl}/models/${key.model}:generateContent?key=${key.key}',
    );
    final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': systemPrompt},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': userPrompt},
                  ],
                },
              ],
              'generationConfig': {
                'maxOutputTokens': OpenAiCompatibleClient.maxTokens,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const ServerError(0);
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthFailure(response.statusCode);
      }
      if (response.statusCode == 429) throw const RateLimited();
      throw ServerError(response.statusCode);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final candidates = (decoded as Map)['candidates'] as List?;
      final parts =
          ((candidates?.first as Map?)?['content'] as Map?)?['parts'] as List?;
      final text = parts
          ?.whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (text == null || text.trim().isEmpty) throw const MalformedResponse();
      return text;
    } catch (_) {
      throw const MalformedResponse();
    }
  }
}

/// The providers offered for a personal key, with their default endpoint and
/// model. `custom` is absent on purpose: that option exists for an endpoint
/// only its owner knows.
class OwnKeyProvider {
  const OwnKeyProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.model,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String model;

  static const List<OwnKeyProvider> all = [
    OwnKeyProvider(
      id: 'openrouter',
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-4o-mini',
    ),
    OwnKeyProvider(
      id: 'google',
      label: 'Google AI Studio',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.0-flash',
    ),
    OwnKeyProvider(
      id: 'custom',
      label: 'Custom endpoint',
      baseUrl: '',
      model: '',
    ),
  ];

  static OwnKeyProvider? byId(String id) {
    for (final provider in all) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}
