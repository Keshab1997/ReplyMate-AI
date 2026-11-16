import 'dart:convert';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:http/http.dart' as http;

/// Every way an AI call can fail, typed so the repository can map each one to
/// an honest, retryable-or-not user message
/// "Failure handling").
sealed class AiCallException implements Exception {
  const AiCallException();

  int get statusCode;
  String get userMessage;
  bool get isRetryable;
}

class AuthFailure extends AiCallException {
  const AuthFailure(this.statusCode);

  @override
  final int statusCode;
  @override
  String get userMessage => 'The API key was rejected by the provider.';
  @override
  bool get isRetryable => false;
}

class RateLimited extends AiCallException {
  const RateLimited();

  @override
  int get statusCode => 429;
  @override
  String get userMessage =>
      'The AI provider rate-limited the request. '
      'Try again in a moment.';
  @override
  bool get isRetryable => true;
}

class ServerError extends AiCallException {
  const ServerError(this.statusCode);

  @override
  final int statusCode;
  @override
  String get userMessage =>
      'The AI provider is unavailable '
      '(status $statusCode).';
  @override
  bool get isRetryable => true;
}

class MalformedResponse extends AiCallException {
  const MalformedResponse();

  @override
  int get statusCode => 200;
  @override
  String get userMessage =>
      'The AI provider returned an unreadable '
      'response.';
  @override
  bool get isRetryable => true;
}

/// The HTTP client behind every pooled key, speaking each provider's own
/// dialect rather than assuming they all do `/chat/completions`.
///
/// That assumption was the bug this comment exists to bury: the admin panel
/// health-checks a `google` key against `generateContent` and prefixes a bare
/// OpenRouter model with its vendor, so a key the admin screen called *healthy*
/// could still fail every app call - a 404 on `/v1beta/chat/completions`, or a
/// 400 for `gpt-4o-mini` where OpenRouter wants `openai/gpt-4o-mini`. A pool
/// whose health check and whose caller disagree is worse than no health check.
/// The HTTP client is injectable so tests can serve canned responses without
/// a socket.
class OpenAiCompatibleClient {
  OpenAiCompatibleClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Enough for two or three short replies in any of the three languages;
  /// a long Bengali reply is more characters than a long English one, which is
  /// why this is not tighter.
  static const int maxTokens = 300;

  Future<String> complete({
    required AdminApiKey key,
    required String systemPrompt,
    required String userPrompt,
    int? maxOutputTokens,
  }) async {
    final budget = maxOutputTokens ?? maxTokens;
    if (key.provider == 'google') {
      return _completeGemini(
        key: key,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxOutputTokens: budget,
      );
    }
    final uri = Uri.parse('${key.baseUrl}/chat/completions');
    final body = jsonEncode({
      // OpenRouter addresses models as `provider/model`; a bare name pasted from
      // another dashboard is rejected there. The package owns that mapping so
      // the health check and the real call cannot drift apart again.
      'model': resolveOpenRouterModel(key.baseUrl, key.model),
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.7,
      // A chat reply is a line or two. Without a cap, providers bill the model's
      // default completion length even when it stops early, and one generous
      // default is the difference between a free month and a bill.
      'max_tokens': budget,
    });
    final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              // charset=utf-8 is load-bearing: package:http encodes String
              // bodies as latin-1 unless the content type says otherwise,
              // and Bengali / Devanagari replies are not latin-1.
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${key.key}',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      // DNS, TLS, timeout, socket reset: all "the provider could not be
      // reached", all worth a retry with another key.
      throw const ServerError(0);
    }
    switch (response.statusCode) {
      case 200:
        // Decode the bytes as UTF-8 ourselves: providers commonly omit the
        // charset on their content type, and package:http would otherwise
        // decode Bengali / Devanagari as latin-1 mojibake.
        return _extractContent(utf8.decode(response.bodyBytes));
      case 401:
      case 403:
        throw AuthFailure(response.statusCode);
      case 429:
        throw const RateLimited();
      default:
        throw ServerError(response.statusCode);
    }
  }

  /// Gemini speaks its own shape: the key rides in the query string, the
  /// prompt is `contents`, and the reply is in `candidates[0].content.parts`.
  /// Kept beside the OpenAI path rather than in a subclass because there are
  /// exactly two dialects and a hierarchy for two is more code, not less.
  Future<String> _completeGemini({
    required AdminApiKey key,
    required String systemPrompt,
    required String userPrompt,
    required int maxOutputTokens,
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
                'maxOutputTokens': maxOutputTokens,
                // Constrained JSON: the shared prompt asks for the same
                // envelope every other provider returns, and the parser in
                // KeyPoolReplyRepository reads it.
                'responseMimeType': 'application/json',
                'responseSchema': {
                  'type': 'OBJECT',
                  'properties': {
                    'replies': {
                      'type': 'ARRAY',
                      'items': {'type': 'STRING'},
                    },
                  },
                  'required': ['replies'],
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      throw const ServerError(0);
    }
    if (response.statusCode != 200) _throwForStatus(response.statusCode);
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
    } catch (error) {
      if (error is AiCallException) rethrow;
      throw const MalformedResponse();
    }
  }

  /// One place that decides what a status code means, so the two dialects
  /// cannot classify 401 as retryable in one and not the other.
  Never _throwForStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      throw AuthFailure(statusCode);
    }
    if (statusCode == 429) throw const RateLimited();
    throw ServerError(statusCode);
  }

  /// The `choices[0].message.content` unwrap, used by callers that read an
  /// OpenAI-compatible body themselves.
  static String extractContent(String body) => _decodeContent(body);

  String _extractContent(String body) => _decodeContent(body);

  static String _decodeContent(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, Object?>) {
            final message = first['message'];
            if (message is Map<String, Object?>) {
              final content = message['content'];
              if (content is String && content.trim().isNotEmpty) {
                return content;
              }
            }
          }
        }
      }
    } on FormatException {
      // falls through to MalformedResponse
    }
    throw const MalformedResponse();
  }

  void close() => _http.close();
}
