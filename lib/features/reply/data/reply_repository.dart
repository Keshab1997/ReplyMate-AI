import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reply_request.dart';

/// Outcome of a generation attempt. Never throws: every failure mode in
/// docs/AI_INTEGRATION.md ("Failure handling") becomes a [ReplyFailure] the
/// UI can show honestly.
sealed class ReplyResult {
  const ReplyResult();
}

class ReplySuccess extends ReplyResult {
  const ReplySuccess(this.replies);

  final List<String> replies;
}

class ReplyFailure extends ReplyResult {
  const ReplyFailure(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;
}

/// Where suggestions come from. Batch 1 ships only
/// [NotConfiguredReplyRepository]; batch 2 swaps in the Firestore-backed
/// key-pool implementation (admin_api_key_manager) behind this same
/// interface, so no screen changes when the AI backend arrives.
abstract interface class ReplyRepository {
  Future<ReplyResult> generate(ReplyRequest request);
}

/// Honest placeholder: the app is fully usable as a shell, and every
/// generation attempt explains that the AI backend is not configured yet
/// instead of showing a fabricated reply (docs/AI_INTEGRATION.md: "Never
/// display a fabricated reply as a successful AI result").
class NotConfiguredReplyRepository implements ReplyRepository {
  const NotConfiguredReplyRepository();

  @override
  Future<ReplyResult> generate(ReplyRequest request) async {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      return ReplyFailure(problems.join(' '), isRetryable: false);
    }
    return const ReplyFailure(
      'AI backend is not configured on this install yet. '
      'Reply generation arrives with the Firebase key-pool integration; '
      'until then use copy/paste manually.',
      isRetryable: false,
    );
  }
}

/// The repository the UI talks to. main() overrides it with
/// [KeyPoolReplyRepository] when Firebase boots; tests override it with
/// fakes. Nothing ever constructs a repository inside a widget.
final Provider<ReplyRepository> replyRepositoryProvider =
    Provider<ReplyRepository>(
      (Ref ref) => const NotConfiguredReplyRepository(),
    );
