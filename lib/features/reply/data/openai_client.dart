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

/// Minimal OpenAI-compatible `/chat/completions` client - the wire format
/// every provider in the key pool speaks (Gemini proxy, OpenRouter, custom).
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
  }) async {
    final uri = Uri.parse('${key.baseUrl}/chat/completions');
    final body = jsonEncode({
      'model': key.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.7,
      // A chat reply is a line or two. Without a cap, providers bill the model's
      // default completion length even when it stops early, and one generous
      // default is the difference between a free month and a bill.
      'max_tokens': maxTokens,
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

  String _extractContent(String body) {
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
