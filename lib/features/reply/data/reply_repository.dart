import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reply_request.dart';
import 'ai_usage_tracker.dart';
import 'offline_suggestions.dart';
import 'reply_cache.dart';

/// Outcome of a generation attempt. Never throws: every failure mode in
/// ("Failure handling") becomes a [ReplyFailure] the
/// UI can show honestly.
sealed class ReplyResult {
  const ReplyResult();
}

class ReplySuccess extends ReplyResult {
  const ReplySuccess(
    this.replies, {
    this.fromCache = false,
    this.cachedAt,
    this.offline = false,
  });

  final List<String> replies;

  /// True when these came from the on-device cache instead of a paid call.
  /// The UI must say so: a cached reply presented as fresh is a lie about what
  /// just happened, even when it is the same text the provider would return.
  final bool fromCache;

  /// When the cached set was stored, for the "from cache" label.
  final DateTime? cachedAt;

  /// True when these came from the on-device rule layer rather than a model.
  /// They are suggestions, not AI output, and the UI says so — passing them off
  /// as generated would be the one thing this app must never do.
  final bool offline;
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
/// One step of an answer that is still arriving.
///
/// [preview] is what the screen may show *while* it waits: reply strings whose
/// JSON had already closed. It is never an answer - the screen keeps a
/// "writing…" state on top of it, and [done] is the only thing that turns this
/// into a finished turn. A stream that ends without [done] must be shown as a
/// failure, not as the preview the user happened to see.
class ReplyProgress {
  const ReplyProgress(this.preview, {this.result});

  /// Reply strings that are already closed JSON values. A preview only.
  final List<String> preview;

  /// The finished answer, present on the last event only. Null before that.
  /// One object carries both so the stream cannot be "done" without saying
  /// what it produced.
  final ReplyResult? result;

  bool get isFinal => result != null;
}

/// A repository that can also answer while it is answering.
///
/// Kept separate from [ReplyRepository] on purpose: `abstract interface class`
/// members are not inherited by implementers, so folding streaming in would
/// have forced every test double to write a `generateStreaming` stub - and a
/// stub is exactly where a fake preview would creep in. A screen asks
/// `repository is StreamingReplyRepository` and falls back to the ordinary
/// single-answer path otherwise, which is what guest mode does.
abstract interface class StreamingReplyRepository implements ReplyRepository {
  Stream<ReplyProgress> generateStreaming(
    ReplyRequest request, {
    bool bypassCache = false,
  });
}

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

/// Wraps a [ReplyRepository] with a cache and a non-blocking local usage
/// counter. The counter is informational; it never limits provider calls.
///
/// Order matters:
/// 1. **validate** — bad requests do not reach the provider,
/// 2. **cache** — a repeat does not reach the provider,
/// 3. **count** — only an uncached generation attempt is recorded,
/// 4. **inner** — call the configured provider.
///
/// A cache hit costs neither a request nor a count. An uncached attempt is
/// counted before it starts, including failed provider calls, because the
/// attempt still reached the paid path.
class CachedReplyRepository implements StreamingReplyRepository {
  CachedReplyRepository({
    required this.inner,
    ReplyCache? cache,
    this.usageTracker,
  }) : _cache = cache ?? ReplyCache.disabled();

  final ReplyRepository inner;
  final ReplyCache _cache;

  /// One-event stream for a non-streaming inner repository.
  Stream<ReplyProgress> _singleAnswer(ReplyRequest request) async* {
    final result = await inner.generate(request, bypassCache: true);
    final preview = switch (result) {
      ReplySuccess(:final replies) => replies,
      ReplyFailure() => const <String>[],
    };
    yield ReplyProgress(preview, result: result);
  }

  @override
  Stream<ReplyProgress> generateStreaming(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async* {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      final failure = ReplyFailure(problems.join(' '));
      yield ReplyProgress(const <String>[], result: failure);
      return;
    }
    // A stored answer has nothing to stream, and typing one out on screen would
    // be theatre - the user would watch a lie arrive slowly. Streaming is
    // therefore always a live call, and the cache is only written at the end.
    final cacheEligible = request.draftToRefine == null;
    await usageTracker?.recordAttempt();
    // The inner repository is always the pooled one in production; a wrapper
    // around a repository that cannot stream simply yields its single answer,
    // which is a preview-less stream rather than a second code path here.
    final streaming = inner;
    final source = streaming is StreamingReplyRepository
        ? streaming.generateStreaming(request, bypassCache: true)
        : _singleAnswer(request);
    await for (final progress in source) {
      final result = progress.result;
      if (result is ReplySuccess &&
          result.replies.isNotEmpty &&
          cacheEligible) {
        await _cache.store(request, result.replies);
      }
      yield progress;
    }
  }

  /// Exposed so Settings can show an informational local count.
  final AiUsageTracker? usageTracker;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    final problems = request.validate();
    if (problems.isNotEmpty) {
      return ReplyFailure(problems.join(' '), isRetryable: false);
    }

    // Rewrites include the user's existing draft as well as the incoming
    // message. Do not persist that text in the reply cache, even as a cache key.
    final cacheEligible = request.draftToRefine == null;
    final cached = bypassCache || !cacheEligible
        ? null
        : _cache.lookup(request);
    if (cached != null) {
      return ReplySuccess(
        cached.replies,
        fromCache: true,
        cachedAt: cached.storedAt,
      );
    }

    await usageTracker?.recordAttempt();
    final result = await inner.generate(request, bypassCache: bypassCache);
    if (result is ReplySuccess && result.replies.isNotEmpty) {
      if (cacheEligible) await _cache.store(request, result.replies);
      return result;
    }

    // A failed rewrite cannot honestly fall back to an unrelated offline reply
    // to the incoming message. Keep the original draft and report the failure.
    // Intent chips and standalone writing briefs need task-aware wording;
    // generic offline candidates could contradict either request, so keep the
    // honest failure instead of returning an unrelated draft.
    if (request.draftToRefine != null || request.replyIntent != null) {
      return result;
    }

    // The paid path failed. Before giving up, offer what the rules can write:
    // no key, no network, no tokens. They are labelled offline by the caller,
    // so the user knows exactly what they are looking at.
    //
    // A standalone writing brief gets the same treatment: a first-run user with
    // no key used to get "no provider" and nothing else, which made the writer
    // look broken rather than unconfigured. On-device openers are not a model's
    // writing and are labelled as such - but they are something to start from.
    if (request.mode == ReplyMode.createMessage) {
      final starters = OfflineSuggestions.forBrief(
        request.trimmedMessage,
        language: request.language,
        tone: request.tone,
        length: request.length,
        count: request.count,
      );
      if (starters.isNotEmpty) return ReplySuccess(starters, offline: true);
      return result;
    }

    final offline = OfflineSuggestions.forMessage(
      request.trimmedMessage,
      language: request.language,
      tone: request.tone,
      length: request.length,
      count: request.count,
    );
    if (offline.isNotEmpty) {
      return ReplySuccess(offline, offline: true);
    }
    return result;
  }

  /// The offline candidates for a request, without attempting a paid call.
  /// Used after provider failures so the screen can still offer something
  /// rather than a dead end.
  List<String> offlineOnly(ReplyRequest request) {
    if (request.replyIntent != null) return const <String>[];
    // A standalone brief has its own on-device starters; the reply table would
    // be answering a message that does not exist.
    if (request.mode == ReplyMode.createMessage) {
      return OfflineSuggestions.forBrief(
        request.trimmedMessage,
        language: request.language,
        tone: request.tone,
        length: request.length,
        count: request.count,
      );
    }
    return OfflineSuggestions.forMessage(
      request.trimmedMessage,
      language: request.language,
      tone: request.tone,
      length: request.length,
      count: request.count,
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
