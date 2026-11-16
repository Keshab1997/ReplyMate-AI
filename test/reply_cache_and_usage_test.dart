import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/ai_usage_tracker.dart';
import 'package:replymate/features/reply/data/reply_cache.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_intent.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

/// Decodes [value] as base64, or returns '' when it is not base64 at all —
/// which is itself the proof that a key is not merely an encoding.
String base64UrlDecodeToText(String value) {
  try {
    return utf8.decode(base64Url.decode(base64Url.normalize(value)));
  } catch (_) {
    return '';
  }
}

ReplyRequest _request({
  String message = 'kal asbo?',
  ReplyLanguage language = ReplyLanguage.bengali,
  ReplyTone tone = ReplyTone.friendly,
  ReplyLength length = ReplyLength.short,
  int count = 1,
  List<String> prior = const [],
  String? draftToRefine,
  String? refinementInstruction,
  ReplyIntent? replyIntent,
}) => ReplyRequest(
  message: message,
  language: language,
  tone: tone,
  length: length,
  count: count,
  priorMessages: prior,
  draftToRefine: draftToRefine,
  refinementInstruction: refinementInstruction,
  replyIntent: replyIntent,
);

/// Counts calls and returns whatever the test asked for.
class FailingRepository implements ReplyRepository {
  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async => const ReplyFailure('provider unavailable');
}

class _CountingRepository implements ReplyRepository {
  _CountingRepository([this.reply = 'ঠিক আছে']);

  String reply;
  int calls = 0;
  bool lastBypassed = false;

  @override
  Future<ReplyResult> generate(
    ReplyRequest request, {
    bool bypassCache = false,
  }) async {
    calls++;
    lastBypassed = bypassCache;
    return ReplySuccess([reply]);
  }
}

void main() {
  setUpAll(() async {
    Hive.init('/tmp/replymate_cache_test');
  });

  Future<Box<dynamic>> freshBox(String name) async {
    final box = Hive.isBoxOpen(name)
        ? Hive.box<dynamic>(name)
        : await Hive.openBox<dynamic>(name);
    await box.clear();
    return box;
  }

  group('cache key', () {
    test('every field that changes the answer changes the key', () {
      final base = ReplyCache.keyFor(_request(message: 'hello there'));
      expect(ReplyCache.keyFor(_request(message: 'hello there')), base);

      expect(ReplyCache.keyFor(_request(message: 'hello world')), isNot(base));
      expect(
        ReplyCache.keyFor(
          _request(message: 'hello there', tone: ReplyTone.funny),
        ),
        isNot(base),
      );
      expect(
        ReplyCache.keyFor(
          _request(message: 'hello there', language: ReplyLanguage.hindi),
        ),
        isNot(base),
      );
      expect(
        ReplyCache.keyFor(_request(message: 'hello there', count: 3)),
        isNot(base),
      );
      expect(
        ReplyCache.keyFor(_request(message: 'hello there', prior: ['earlier'])),
        isNot(base),
      );
      expect(
        ReplyCache.keyFor(
          _request(message: 'hello there')
              .copyWith(replyIntent: ReplyIntent.agree),
        ),
        isNot(base),
      );
      expect(
        ReplyCache.keyFor(
          _request(message: 'hello there')
              .copyWith(mode: ReplyMode.createMessage),
        ),
        isNot(base),
      );
    });

    test('the key is a hash: it cannot be read back into the message', () {
      // The cache is on disk, so its keys are on disk. A base64 key was the
      // message itself; conversation memory is the only feature allowed to
      // write message text there.
      const message = 'tomar sathe coffee kothay';
      final key = ReplyCache.keyFor(_request(message: message));
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      // The v1 scheme, for contrast: reversible in one line, no key needed.
      final legacy = base64Url.encode(utf8.encode(message));
      expect(base64UrlDecodeToText(legacy), message);
      // And the current one is not.
      expect(base64UrlDecodeToText(key), isNot(contains('coffee')));
      expect(key.toLowerCase(), isNot(contains('coffee')));
    });

    test('surrounding whitespace does not split the cache', () {
      // trimmedMessage is what the prompt sends, so it is what the key uses.
      expect(
        ReplyCache.keyFor(_request(message: '  hello  ')),
        ReplyCache.keyFor(_request(message: 'hello')),
      );
    });
  });

  group('time sensitivity', () {
    test('a message about time is never cached', () {
      for (final message in [
        'kal asbo?',
        'আজ দেখা হবে?',
        'आज मिलेंगे?',
        'tomorrow at 5?',
        'see you at 18:30',
        'call me at 5 pm',
        'reach by 9am',
        'on 12/05 then',
        'in an hour',
      ]) {
        expect(
          ReplyCache.isTimeSensitive(message),
          isTrue,
          reason: '"$message" should be treated as time-sensitive',
        );
      }
    });

    test('an "am"/"pm" inside a word is not a clock time', () {
      // `contains('am ')` made all of these cache misses for no reason.
      for (final message in [
        'I am fine',
        'team lunch?',
        'shameless plug',
        'grammar check please',
      ]) {
        expect(ReplyCache.isTimeSensitive(message), isFalse, reason: message);
      }
    });

    test('an ordinary message is cacheable', () {
      for (final message in ['ok', 'thanks!', 'ধন্যবাদ', 'হুম', 'nice one']) {
        expect(ReplyCache.isTimeSensitive(message), isFalse, reason: message);
      }
    });
  });

  group('ReplyCache', () {
    test('stores and returns a reply set, with its age', () async {
      final box = await freshBox('cache_roundtrip');
      final now = DateTime(2026, 5, 1, 12);
      final cache = ReplyCache(box: box, clock: () => now);
      final request = _request(message: 'thanks');

      expect(cache.lookup(request), isNull);
      await cache.store(request, ['ঠিক আছে', 'ধন্যবাদ']);

      final hit = cache.lookup(request)!;
      expect(hit.replies, ['ঠিক আছে', 'ধন্যবাদ']);
      expect(hit.storedAt, now);
    });

    test('an expired entry is a miss and is deleted', () async {
      final box = await freshBox('cache_expiry');
      var now = DateTime(2026, 5, 1);
      final cache = ReplyCache(
        box: box,
        ttl: const Duration(days: 7),
        clock: () => now,
      );
      final request = _request(message: 'thanks');
      await cache.store(request, ['ok']);

      now = now.add(const Duration(days: 8));
      expect(cache.lookup(request), isNull);
      // Deleted, not merely ignored: leaving it would grow the box forever.
      expect(box.length, 0);
    });

    test('a time-sensitive message is never stored', () async {
      final box = await freshBox('cache_time');
      final cache = ReplyCache(box: box);
      await cache.store(_request(message: 'kal dekha hobe?'), ['ok']);
      expect(box.length, 0);
    });

    test('a disabled cache stores nothing and never throws', () async {
      final cache = ReplyCache.disabled();
      final request = _request(message: 'thanks');
      await cache.store(request, ['ok']);
      expect(cache.lookup(request), isNull);
    });

    test('the box stays bounded', () async {
      final box = await freshBox('cache_bound');
      var now = DateTime(2026, 1, 1);
      final cache = ReplyCache(box: box, clock: () => now);
      // 320 distinct messages against a 300-entry cap.
      for (var i = 0; i < 320; i++) {
        now = now.add(const Duration(seconds: 1));
        await cache.store(_request(message: 'message $i'), ['ok']);
      }
      expect(box.length, lessThanOrEqualTo(300));
    });
  });

  group('AiUsageTracker', () {
    test('starts empty and counts generation attempts', () async {
      final box = await freshBox('usage_count');
      final tracker = AiUsageTracker(
        box: box,
        clock: () => DateTime(2026, 5, 1),
      );

      expect(tracker.snapshot().used, 0);

      await tracker.recordAttempt();
      await tracker.recordAttempt();
      expect(tracker.snapshot().used, 2);
    });

    test('the informational count rolls over at local midnight', () async {
      final box = await freshBox('usage_rollover');
      var now = DateTime(2026, 5, 1, 23);
      final tracker = AiUsageTracker(box: box, clock: () => now);

      await tracker.recordAttempt();
      await tracker.recordAttempt();
      expect(tracker.snapshot().used, 2);

      now = DateTime(2026, 5, 2, 0, 1);
      expect(tracker.snapshot().used, 0);
    });

    test('tracking failure does not block generation', () async {
      // No box at all: the app still works, the informational count is absent.
      final tracker = AiUsageTracker(box: null);
      await tracker.recordAttempt();
      expect(tracker.snapshot().used, 0);
    });
  });

  group('CachedReplyRepository', () {
    test('a cache hit does not add a generation attempt', () async {
      final box = await freshBox('repo_cache');
      final cache = ReplyCache(box: box);
      final tracker = AiUsageTracker(box: await freshBox('repo_usage'));
      final inner = _CountingRepository();
      final repo = CachedReplyRepository(
        inner: inner,
        cache: cache,
        usageTracker: tracker,
      );
      final request = _request(message: 'thanks a lot');

      final first = await repo.generate(request);
      expect(first, isA<ReplySuccess>());
      expect((first as ReplySuccess).fromCache, isFalse);
      expect(inner.calls, 1);
      expect(tracker.snapshot().used, 1);

      final second = await repo.generate(request);
      expect((second as ReplySuccess).fromCache, isTrue);
      expect(second.cachedAt, isNotNull);
      // The provider was not called, so the local attempt count stays put.
      expect(inner.calls, 1);
      expect(tracker.snapshot().used, 1);
    });

    test('rewrites are never persisted in the reply cache', () async {
      final box = await freshBox('repo_refinement_cache');
      final inner = _CountingRepository();
      final repo = CachedReplyRepository(
        inner: inner,
        cache: ReplyCache(box: box),
      );
      final rewrite = _request(
        message: 'Can we meet tomorrow?',
        draftToRefine: 'Sure, see you then.',
        refinementInstruction: 'Make it shorter.',
      );

      await repo.generate(rewrite);
      await repo.generate(rewrite);

      expect(inner.calls, 2);
      expect(box.length, 0);
    });

    test('bypassCache reaches the provider and replaces the entry', () async {
      final box = await freshBox('repo_bypass');
      final tracker = AiUsageTracker(box: await freshBox('repo_bypass_budget'));
      final inner = _CountingRepository('first');
      final repo = CachedReplyRepository(
        inner: inner,
        cache: ReplyCache(box: box),
        usageTracker: tracker,
      );
      final request = _request(message: 'thanks a lot');

      await repo.generate(request);
      inner.reply = 'second';
      final fresh = await repo.generate(request, bypassCache: true);

      expect(inner.calls, 2);
      expect(inner.lastBypassed, isTrue);
      expect((fresh as ReplySuccess).replies, ['second']);
      expect(fresh.fromCache, isFalse);
      expect(tracker.snapshot().used, 2);
    });

    test('calls continue beyond the former daily cap', () async {
      final tracker = AiUsageTracker(box: await freshBox('repo_no_cap'));
      final inner = _CountingRepository();
      final repo = CachedReplyRepository(
        inner: inner,
        cache: ReplyCache.disabled(),
        usageTracker: tracker,
      );

      for (var index = 0; index < 51; index++) {
        final result = await repo.generate(_request(message: 'message $index'));
        expect(result, isA<ReplySuccess>());
      }

      expect(inner.calls, 51);
      expect(tracker.snapshot().used, 51);
    });

    test(
      'generic offline fallback never contradicts a selected intent',
      () async {
        final repo = CachedReplyRepository(
          inner: FailingRepository(),
          cache: ReplyCache.disabled(),
        );
        final intended = _request(
          message: 'Can you come tomorrow?',
          replyIntent: ReplyIntent.politeDecline,
        );

        final result = await repo.generate(intended);

        expect(result, isA<ReplyFailure>());
        expect(repo.offlineOnly(intended), isEmpty);

        final standalone = _request(message: 'Write a love note.')
            .copyWith(mode: ReplyMode.createMessage);
        expect(await repo.generate(standalone), isA<ReplyFailure>());
        expect(repo.offlineOnly(standalone), isEmpty);
      },
    );

    test('an invalid request is neither called nor counted', () async {
      final tracker = AiUsageTracker(box: await freshBox('repo_invalid'));
      final inner = _CountingRepository();
      final repo = CachedReplyRepository(
        inner: inner,
        cache: ReplyCache.disabled(),
        usageTracker: tracker,
      );

      final result = await repo.generate(_request(message: '   '));

      expect(result, isA<ReplyFailure>());
      expect(inner.calls, 0);
      expect(tracker.snapshot().used, 0);
    });
  });
}
