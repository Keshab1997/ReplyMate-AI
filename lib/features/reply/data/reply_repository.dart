import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reply_request.dart';

/// Outcome of a generation attempt. Never throws: every failure mode in
/// ("Failure handling") becomes a [ReplyFailure] the
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

/// Where suggestions come from. `main()` selects the Firestore-backed key-pool
/// repository when Firebase initializes, and leaves the
/// [NotConfiguredReplyRepository] in place for guest mode. The screen depends
/// only on this interface in either case.
abstract interface class ReplyRepository {
  Future<ReplyResult> generate(ReplyRequest request);
}

/// Honest guest-mode fallback: when Firebase/key-pool configuration is
/// unavailable, generation explains that state instead of showing a fabricated
/// reply (: "Never display a fabricated reply as a
/// successful AI result").
class NotConfiguredReplyRepository implements ReplyRepository {
  const NotConfiguredReplyRepository();

  @override
  Future<ReplyResult> generate(ReplyRequest request) async {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      return ReplyFailure(problems.join(' '), isRetryable: false);
    }
    return const ReplyFailure(
      'AI reply generation is not configured on this install. '
      'Firebase or its API-key pool is unavailable; use copy/paste manually '
      'for now.',
      isRetryable: false,
    );
  }
}

/// The repository the UI talks to. `main()` selects the key-pool
/// implementation when Firebase boots; tests override it with fakes. Nothing
/// ever constructs a repository inside a widget.
final Provider<ReplyRepository> replyRepositoryProvider =
    Provider<ReplyRepository>(
      (Ref ref) => const NotConfiguredReplyRepository(),
    );
