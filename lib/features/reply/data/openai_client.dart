import 'dart:convert';
import 'dart:math' as math;

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

  /// Floor for Gemini models, whose 2.5+ releases share `maxOutputTokens`
  /// between internal thinking and the visible JSON answer. Setting a larger
  /// ceiling stops thinking from starving a short reply while the schema keeps
  /// actual output concise.
  static const int _geminiMinTokens = 2048;

  /// Higher ceiling used only when a reasoning / thinking model spends its
  /// initial token budget without producing visible content.
  static const int _reasoningRetryMinTokens = 2048;
  static const int _reasoningRetryMaxTokens = 4096;

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
    return _completeOpenAiCompatible(
      key: key,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      budget: budget,
    );
  }

  Future<String> _completeOpenAiCompatible({
    required AdminApiKey key,
    required String systemPrompt,
    required String userPrompt,
    required int budget,
  }) async {
    final baseUrl = _normalizedBaseUrl(key.baseUrl);
    final uri = Uri.parse('$baseUrl/chat/completions');
    // OpenRouter addresses models as `provider/model`; a bare name pasted from
    // another dashboard is rejected there. The package owns that mapping so
    // the health check and the real call cannot drift apart again.
    final model = resolveOpenRouterModel(baseUrl, key.model.trim());

    var useCompatibleShape = false;
    var response = await _postChatCompletions(
      uri: uri,
      apiKey: key.key,
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      maxTokens: budget,
      temperature: 0.7,
    );

    // The admin panel's ping checks with a single user turn and no temperature.
    // Models like Gemma on OpenRouter or strict reasoning endpoints return 400
    // for `role: system` or `temperature: 0.7` even though the key is healthy.
    if (response.statusCode == 400 || response.statusCode == 422) {
      useCompatibleShape = true;
      response = await _postChatCompletions(
        uri: uri,
        apiKey: key.key,
        model: model,
        messages: [
          {'role': 'user', 'content': '$systemPrompt\n\n$userPrompt'},
        ],
        maxTokens: budget,
      );
    }

    if (response.statusCode != 200) _throwForStatus(response.statusCode);

    // Decode the bytes as UTF-8 ourselves: providers commonly omit the
    // charset on their content type, and package:http would otherwise
    // decode Bengali / Devanagari as latin-1 mojibake.
    var inspected = _inspectChatCompletion(utf8.decode(response.bodyBytes));
    if (inspected.content != null) return inspected.content!;

    // Reasoning models on OpenRouter / OpenAI-compatible proxies can spend
    // the entire 300-token chat budget in `reasoning` / `reasoning_content` /
    // `<think>` and return `content: null` with `finish_reason: "length"` while
    // passing the 5-token admin ping with HTTP 200. Retry once with room.
    if (inspected.shouldRetryForReasoning &&
        budget < _reasoningRetryMaxTokens) {
      final retryBudget = (budget * 4).clamp(
        _reasoningRetryMinTokens,
        _reasoningRetryMaxTokens,
      );
      response = await _postChatCompletions(
        uri: uri,
        apiKey: key.key,
        model: model,
        messages: useCompatibleShape
            ? [
                {'role': 'user', 'content': '$systemPrompt\n\n$userPrompt'},
              ]
            : [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
        maxTokens: retryBudget,
        temperature: useCompatibleShape ? null : 0.7,
      );
      if (response.statusCode != 200) _throwForStatus(response.statusCode);
      inspected = _inspectChatCompletion(utf8.decode(response.bodyBytes));
      if (inspected.content != null) return inspected.content!;
    }

    throw const MalformedResponse();
  }

  Future<http.Response> _postChatCompletions({
    required Uri uri,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required int maxTokens,
    double? temperature,
  }) async {
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': ?temperature,
      // A chat reply is a line or two. Without a cap, providers bill the model's
      // default completion length even when it stops early, and one generous
      // default is the difference between a free month and a bill.
      'max_tokens': maxTokens,
    });
    try {
      return await _http
          .post(
            uri,
            headers: {
              // charset=utf-8 is load-bearing: package:http encodes String
              // bodies as latin-1 unless the content type says otherwise,
              // and Bengali / Devanagari replies are not latin-1.
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $apiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      // DNS, TLS, timeout, socket reset: all "the provider could not be
      // reached", all worth a retry with another key.
      throw const ServerError(0);
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
    final baseUrl = _normalizedBaseUrl(key.baseUrl);
    final model = key.model.trim().replaceFirst(RegExp(r'^models/'), '');
    final uri = Uri.parse(
      '$baseUrl/models/$model:generateContent?key=${key.key}',
    );
    // Gemma models served on Google AI Studio reject both `systemInstruction`
    // and JSON-mode `responseSchema` with HTTP 400 while still passing the
    // admin health ping with HTTP 200.
    var useStructuredGemini = !model.toLowerCase().contains('gemma');
    final initialBudget = useStructuredGemini
        ? math.max(maxOutputTokens, _geminiMinTokens)
        : maxOutputTokens;

    var response = await _postGemini(
      uri: uri,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxOutputTokens: initialBudget,
      structured: useStructuredGemini,
    );

    if (response.statusCode == 400 && useStructuredGemini) {
      useStructuredGemini = false;
      response = await _postGemini(
        uri: uri,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxOutputTokens: initialBudget,
        structured: false,
      );
    }

    if (response.statusCode != 200) _throwForStatus(response.statusCode);

    var inspected = _inspectGeminiResponse(utf8.decode(response.bodyBytes));
    if (inspected.text != null) return inspected.text!;

    if (inspected.finishReason == 'MAX_TOKENS' &&
        initialBudget < _reasoningRetryMaxTokens) {
      response = await _postGemini(
        uri: uri,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxOutputTokens: _reasoningRetryMaxTokens,
        structured: useStructuredGemini,
      );
      if (response.statusCode != 200) _throwForStatus(response.statusCode);
      inspected = _inspectGeminiResponse(utf8.decode(response.bodyBytes));
      if (inspected.text != null) return inspected.text!;
    }

    throw const MalformedResponse();
  }

  Future<http.Response> _postGemini({
    required Uri uri,
    required String systemPrompt,
    required String userPrompt,
    required int maxOutputTokens,
    required bool structured,
  }) async {
    final payload = structured
        ? {
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
          }
        : {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': '$systemPrompt\n\n$userPrompt'},
                ],
              },
            ],
            'generationConfig': {'maxOutputTokens': maxOutputTokens},
          };
    try {
      return await _http
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      throw const ServerError(0);
    }
  }

  static String _normalizedBaseUrl(String raw) =>
      raw.trim().replaceFirst(RegExp(r'/+$'), '');

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

  static String _decodeContent(String body) {
    final inspected = _inspectChatCompletion(body);
    if (inspected.content != null) return inspected.content!;
    throw const MalformedResponse();
  }

  static ({String? content, bool shouldRetryForReasoning})
  _inspectChatCompletion(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, Object?>) {
            final finishReason = first['finish_reason'];
            final message = first['message'];
            if (message is Map<String, Object?>) {
              final raw = _extractMessageText(message['content']);
              final unclosedThink = raw != null && _isOnlyUnclosedThinking(raw);
              if (raw != null && raw.trim().isNotEmpty && !unclosedThink) {
                return (content: raw, shouldRetryForReasoning: false);
              }
              final hasReasoning =
                  _nonEmptyValue(message['reasoning']) ||
                  _nonEmptyValue(message['reasoning_content']) ||
                  _nonEmptyValue(message['reasoning_details']);
              final shouldRetry =
                  finishReason == 'length' || hasReasoning || unclosedThink;
              return (content: null, shouldRetryForReasoning: shouldRetry);
            }
          }
        }
      }
    } on FormatException {
      // falls through to MalformedResponse
    }
    return (content: null, shouldRetryForReasoning: false);
  }

  static String? _extractMessageText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          if (part['type'] == 'thinking' || part['thought'] == true) continue;
          final text = part['text'];
          if (text is String) buffer.write(text);
        }
      }
      final joined = buffer.toString();
      return joined.isEmpty ? null : joined;
    }
    return null;
  }

  static bool _isOnlyUnclosedThinking(String text) {
    final lower = text.trim().toLowerCase();
    return lower.startsWith('<think>') && !lower.contains('</think>');
  }

  static bool _nonEmptyValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static ({String? text, String? finishReason}) _inspectGeminiResponse(
    String body,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return (text: null, finishReason: null);
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        return (text: null, finishReason: null);
      }
      final first = candidates.first;
      if (first is! Map) return (text: null, finishReason: null);
      final finishReason = first['finishReason'] as String?;
      final parts = (first['content'] as Map?)?['parts'] as List?;
      final text = parts
          ?.whereType<Map>()
          // Gemini 2.5+ thinking models emit `{"thought": true, "text": "..."}`
          // parts ahead of the answer; mixing them in breaks JSON parsing.
          .where((part) => part['thought'] != true)
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (text == null || text.trim().isEmpty) {
        return (text: null, finishReason: finishReason);
      }
      return (text: text, finishReason: finishReason);
    } on FormatException {
      return (text: null, finishReason: null);
    }
  }

  void close() => _http.close();
}
