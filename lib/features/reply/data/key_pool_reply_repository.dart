import 'dart:convert';

import 'key_source.dart';
import 'openai_client.dart';
import 'prompt_builder.dart';
import 'reply_repository.dart';
import '../domain/reply_request.dart';

/// The production [ReplyRepository]: pulls a healthy key from the
/// admin-managed Firestore pool and calls the provider's
/// `/chat/completions` endpoint directly (architecture A, recorded in
/// "Key-pool decision").
/// Every failure path returns a [ReplyFailure] with an honest message and a
/// correct retryable flag; a key that misbehaved is reported back to the pool
/// so its cooldown / deactivation logic can act.
class KeyPoolReplyRepository implements ReplyRepository {
  KeyPoolReplyRepository({KeySource? keys, OpenAiCompatibleClient? client})
    : _keys = keys ?? const ApiKeyManagerKeySource(),
      _client = client ?? OpenAiCompatibleClient();

  final KeySource _keys;
  final OpenAiCompatibleClient _client;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    // The pool has no cache of its own; the flag is honoured by the layer that
    // wraps it and is accepted here to keep the interface uniform.
    bool bypassCache = false,
  }) async {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      return ReplyFailure(problems.join(' '));
    }
    final key = _keys.next();
    if (key == null) {
      return const ReplyFailure(
        'No healthy API key is available right now. The admin key pool is '
        'empty, cooling down, or not configured on this install.',
        isRetryable: true,
      );
    }
    try {
      final content = await _client.complete(
        key: key,
        systemPrompt: ReplyPrompt.system(
          request.count,
          request.tone,
          styleExamples: request.styleExamples,
          mode: request.mode,
        ),
        userPrompt: ReplyPrompt.user(request),
      );
      _keys.reportSuccess(key);
      final replies = parseReplies(content, request.count);
      if (replies.isEmpty) {
        return const ReplyFailure(
          'The AI provider returned an empty suggestion list.',
          isRetryable: true,
        );
      }
      return ReplySuccess(replies);
    } on AiCallException catch (error) {
      _keys.reportFailure(key, error.statusCode);
      return ReplyFailure(error.userMessage, isRetryable: error.isRetryable);
    } catch (error) {
      _keys.reportFailure(key, 0);
      return const ReplyFailure(
        'Network problem while reaching the AI provider.',
        isRetryable: true,
      );
    }
  }

  /// Normalizes the structured reply contract shared by every provider. Models may add Markdown fences, double-encode the JSON, or
  /// truncate the final brackets. Recover complete message strings where safe;
  /// never turn a JSON envelope or malformed fragment into a user-facing reply.
  static List<String> parseReplies(String content, int count) {
    if (count <= 0) return const <String>[];
    final text = _withoutCodeFence(content).trim();
    if (text.isEmpty) return const <String>[];

    final direct = _parseStructured(text, count);
    if (direct != null) return direct;

    final object = _firstJsonObject(text);
    if (object != null) {
      final extracted = _parseStructured(object, count);
      if (extracted != null) return extracted;
    }

    final recovered = _recoverReplyStrings(text, count);
    if (recovered.isNotEmpty) return recovered;

    // A malformed structured response is a retryable provider failure, not
    // message text. The repository handles an empty result without exposing it.
    if (_looksLikeStructuredOutput(text)) return const <String>[];

    // Some providers ignore JSON mode entirely. Keep that compatibility path,
    // but strip list markers and surrounding quotation marks from each reply.
    return text
        .split(RegExp(r'\r?\n'))
        .map(_cleanPlainLine)
        .where((line) => line.isNotEmpty)
        .take(count)
        .toList();
  }

  static String _withoutCodeFence(String content) {
    final trimmed = content.trim();
    final withoutOpening = trimmed.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    return withoutOpening.replaceFirst(RegExp(r'\s*```$'), '').trim();
  }

  /// `null` means unrecognized structure; an empty list is a recognized but
  /// empty answer and must stay a failure instead of falling back to raw text.
  static List<String>? _parseStructured(String candidate, int count) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is String) {
        final nested = decoded.trim();
        if (nested.startsWith('{') || nested.startsWith('[')) {
          return _parseStructured(nested, count);
        }
        return null;
      }
      if (decoded is List) return _stringReplies(decoded, count);
      if (decoded is Map) {
        for (final key in const ['replies', 'suggestions']) {
          if (!decoded.containsKey(key)) continue;
          final value = decoded[key];
          if (value is List) return _stringReplies(value, count);
          if (value is String && value.trim().isNotEmpty) {
            return <String>[value.trim()].take(count).toList();
          }
          return const <String>[];
        }
        for (final key in const ['reply', 'suggestion']) {
          final value = decoded[key];
          if (value is String && value.trim().isNotEmpty) {
            return <String>[value.trim()].take(count).toList();
          }
        }
      }
    } on FormatException {
      // Try an embedded balanced object and recover complete strings below.
    }
    return null;
  }

  static List<String> _stringReplies(List<dynamic> values, int count) => values
      .whereType<String>()
      .map((reply) => reply.trim())
      .where((reply) => reply.isNotEmpty)
      .take(count)
      .toList();

  /// Extracts the first balanced object while respecting braces in strings.
  static String? _firstJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, index + 1);
      }
    }
    return null;
  }

  /// Recovers only complete JSON string elements from a truncated replies
  /// array, preserving escaped characters and rejecting keys/fragments.
  static List<String> _recoverReplyStrings(String text, int count) {
    final property = RegExp(
      r'''["']replies["']\s*:\s*\[''',
      caseSensitive: false,
    ).firstMatch(text);
    if (property == null) return const <String>[];
    var index = property.end;
    final replies = <String>[];

    while (index < text.length && replies.length < count) {
      while (index < text.length &&
          (text[index].trim().isEmpty || text[index] == ',')) {
        index++;
      }
      if (index >= text.length || text[index] == ']' || text[index] == '}') {
        break;
      }
      if (text[index] != '"') {
        while (index < text.length &&
            text[index] != ',' &&
            text[index] != ']' &&
            text[index] != '}') {
          index++;
        }
        continue;
      }

      final start = index++;
      var escaped = false;
      var closed = false;
      while (index < text.length) {
        final char = text[index];
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          index++;
          closed = true;
          try {
            final value = jsonDecode(text.substring(start, index));
            if (value is String && value.trim().isNotEmpty) {
              replies.add(value.trim());
            }
          } on FormatException {
            // Ignore malformed elements; continue only at a safe separator.
          }
          break;
        }
        index++;
      }
      if (!closed) break;
    }
    return replies;
  }

  static bool _looksLikeStructuredOutput(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.startsWith('```') ||
        RegExp(
          r'''["']?(?:replies|suggestions)["']?\s*:''',
          caseSensitive: false,
        ).hasMatch(text);
  }

  static String _cleanPlainLine(String line) {
    var cleaned = line.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s+'), '');
    cleaned = cleaned.trim();
    final wrapped =
        (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith('“') && cleaned.endsWith('”')) ||
        (cleaned.startsWith('‘') && cleaned.endsWith('’'));
    if (cleaned.length >= 2 && wrapped) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }
}
