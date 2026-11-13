import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/ai_budget.dart';
import 'package:replymate/features/reply/data/reply_cache.dart';
import 'package:replymate/features/reply/data/reply_repository.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

ReplyRequest _request({
  String message = 'kal asbo?',
  ReplyLanguage language = ReplyLanguage.bengali,
  ReplyTone tone = ReplyTone.friendly,
  ReplyLength length = ReplyLength.short,
  int count = 1,
  List<String> prior = const [],
}) => ReplyRequest(
  message: message,
  language: language,
  tone: tone,
  length: length,
  count: count,
  priorMessages: prior,
);

/// Counts calls and returns whatever the test asked for.
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

  group('AiBudget', () {
    test('starts empty and counts up', () async {
      final box = await freshBox('budget_count');
      final budget = AiBudget(
        box: box,
        limit: 3,
        clock: () => DateTime(2026, 5, 1),
      );

      expect(budget.snapshot().used, 0);
      expect(budget.canSpend, isTrue);

      await budget.record();
      await budget.record();
      expect(budget.snapshot().used, 2);
      expect(budget.canSpend, isTrue);

      await budget.record();
      expect(budget.canSpend, isFalse);
      expect(budget.snapshot().remaining, 0);
    });

    test('a new day is a new allowance, without a write', () async {
      final box = await freshBox('budget_rollover');
      var now = DateTime(2026, 5, 1, 23);
      final budget = AiBudget(box: box, limit: 2, clock: () => now);

      await budget.record();
      await budget.record();
      expect(budget.canSpend, isFalse);

      now = DateTime(2026, 5, 2, 0, 1);
      expect(budget.snapshot().used, 0);
      expect(budget.canSpend, isTrue);
    });

    test('fails open when the box cannot be read', () async {
      // No box at all: the app must still work, the counter just does nothing.
      final budget = AiBudget(box: null, limit: 1);
      expect(budget.canSpend, isTrue);
      await budget.record();
      expect(budget.snapshot().used, 0);
    });
  });

  group('BudgetedReplyRepository', () {
    test('a cache hit costs neither a call nor allowance', () async {
      final box = await freshBox('repo_cache');
      final cache = ReplyCache(box: box);
      final budget = AiBudget(box: await freshBox('repo_budget'), limit: 5);
      final inner = _CountingRepository();
      final repo = BudgetedReplyRepository(
        inner: inner,
        cache: cache,
        budget: budget,
      );
      final request = _request(message: 'thanks a lot');

      final first = await repo.generate(request);
      expect(first, isA<ReplySuccess>());
      expect((first as ReplySuccess).fromCache, isFalse);
      expect(inner.calls, 1);
      expect(budget.snapshot().used, 1);

      final second = await repo.generate(request);
      expect((second as ReplySuccess).fromCache, isTrue);
      expect(second.cachedAt, isNotNull);
      // The whole point: the provider was not called and nothing was spent.
      expect(inner.calls, 1);
      expect(budget.snapshot().used, 1);
    });

    test('bypassCache reaches the provider and replaces the entry', () async {
      final box = await freshBox('repo_bypass');
      final budget = AiBudget(
        box: await freshBox('repo_bypass_budget'),
        limit: 5,
      );
      final inner = _CountingRepository('first');
      final repo = BudgetedReplyRepository(
        inner: inner,
        cache: ReplyCache(box: box),
        budget: budget,
      );
      final request = _request(message: 'thanks a lot');

      await repo.generate(request);
      inner.reply = 'second';
      final fresh = await repo.generate(request, bypassCache: true);

      expect(inner.calls, 2);
      expect(inner.lastBypassed, isTrue);
      expect((fresh as ReplySuccess).replies, ['second']);
      expect(fresh.fromCache, isFalse);
      expect(budget.snapshot().used, 2);
    });

    test('an exhausted budget refuses before calling the provider', () async {
      final budget = AiBudget(box: await freshBox('repo_limit'), limit: 1);
      final inner = _CountingRepository();
      final repo = BudgetedReplyRepository(
        inner: inner,
        cache: ReplyCache.disabled(),
        budget: budget,
      );

      await repo.generate(_request(message: 'one'));
      final second = await repo.generate(_request(message: 'two'));

      expect(second, isA<ReplyFailure>());
      expect((second as ReplyFailure).message, contains('allowance'));
      // Refused, not attempted: no provider call, and no extra allowance spent.
      expect(inner.calls, 1);
      expect(budget.snapshot().used, 1);
    });

    test('an invalid request spends nothing', () async {
      final budget = AiBudget(box: await freshBox('repo_invalid'), limit: 5);
      final inner = _CountingRepository();
      final repo = BudgetedReplyRepository(
        inner: inner,
        cache: ReplyCache.disabled(),
        budget: budget,
      );

      final result = await repo.generate(_request(message: '   '));

      expect(result, isA<ReplyFailure>());
      expect(inner.calls, 0);
      expect(budget.snapshot().used, 0);
    });
  });
}
