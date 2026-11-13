import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reply_request.dart';
import 'ai_budget.dart';
import 'reply_cache.dart';

/// Outcome of a generation attempt. Never throws: every failure mode in
/// ("Failure handling") becomes a [ReplyFailure] the
/// UI can show honestly.
sealed class ReplyResult {
  const ReplyResult();
}

class ReplySuccess extends ReplyResult {
  const ReplySuccess(this.replies, {this.fromCache = false, this.cachedAt});

  final List<String> replies;

  /// True when these came from the on-device cache instead of a paid call.
  /// The UI must say so: a cached reply presented as fresh is a lie about what
  /// just happened, even when it is the same text the provider would return.
  final bool fromCache;

  /// When the cached set was stored, for the "from cache" label.
  final DateTime? cachedAt;
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
  /// [bypassCache] asks for a genuinely fresh answer: it skips the on-device
  /// reply cache and is the only thing that makes a cache hit acceptable —
  /// without an exit, a stale reply would be a trap rather than a saving.
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  });
}

/// Honest guest-mode fallback: when Firebase/key-pool configuration is
/// unavailable, generation explains that state instead of showing a fabricated
/// reply (: "Never display a fabricated reply as a
/// successful AI result").
class NotConfiguredReplyRepository implements ReplyRepository {
  const NotConfiguredReplyRepository();

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
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

/// Wraps a [ReplyRepository] with the two things that keep an app free:
/// a cache in front of it and a daily ceiling behind it.
///
/// Order matters and is the whole design:
/// 1. **validate** — a bad request must not spend anything,
/// 2. **cache** — a repeat must not reach the provider at all,
/// 3. **budget** — only a call that is about to be made is counted,
/// 4. **inner** — the real repository.
///
/// A cache hit therefore costs neither a request nor a penny of allowance,
/// while a miss is counted *before* it is attempted so a failed call still
/// counts: the provider was reached either way, and a counter that forgets
/// failures is a counter that can be farmed by retrying.
class BudgetedReplyRepository implements ReplyRepository {
  BudgetedReplyRepository({required this.inner, ReplyCache? cache, this.budget})
    : _cache = cache ?? ReplyCache.disabled();

  final ReplyRepository inner;
  final ReplyCache _cache;

  /// Exposed so a settings row can show "N of 50 used today" without knowing
  /// about the composer.
  final AiBudget? budget;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      return ReplyFailure(problems.join(' '), isRetryable: false);
    }

    final cached = bypassCache ? null : _cache.lookup(request);
    if (cached != null) {
      return ReplySuccess(
        cached.replies,
        fromCache: true,
        cachedAt: cached.storedAt,
      );
    }

    final budget = this.budget;
    if (budget != null && !budget.canSpend) {
      final snapshot = budget.snapshot();
      return ReplyFailure(
        'Today\'s AI allowance is used up (${snapshot.used} of '
        '${snapshot.limit} replies). It resets tomorrow, and the offline '
        'suggestions below still work without any AI.',
        isRetryable: false,
      );
    }

    await budget?.record();
    final result = await inner.generate(request, bypassCache: bypassCache);
    if (result is ReplySuccess && result.replies.isNotEmpty) {
      await _cache.store(request, result.replies);
    }
    return result;
  }
}

/// The repository the UI talks to. `main()` selects the key-pool
/// implementation when Firebase boots; tests override it with fakes. Nothing
/// ever constructs a repository inside a widget.
final Provider<ReplyRepository> replyRepositoryProvider =
    Provider<ReplyRepository>(
      (Ref ref) => const NotConfiguredReplyRepository(),
    );
