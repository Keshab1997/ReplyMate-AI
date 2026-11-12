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
  Future<ReplyResult> generate(ReplyRequest request) async {
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

  /// Accepts the documented JSON shape first; falls back to one reply per
  /// non-empty line so a provider that ignores the format still produces
  /// usable suggestions instead of an error.
  static List<String> parseReplies(String content, int count) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, Object?> && decoded.containsKey('replies')) {
        // The provider answered in the documented shape: honour it exactly,
        // even when the list is empty (an empty answer is a failure the
        // repository reports, not something to paper over with line-splitting).
        final replies = decoded['replies'];
        if (replies is List) {
          return replies
              .whereType<String>()
              .map((reply) => reply.trim())
              .where((reply) => reply.isNotEmpty)
              .take(count)
              .toList();
        }
      }
    } on FormatException {
      // not JSON: line fallback below
    }
    return content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(count)
        .toList();
  }
}
