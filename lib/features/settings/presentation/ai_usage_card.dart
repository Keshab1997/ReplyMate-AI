import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../reply/data/ai_budget.dart';
import '../../reply/data/reply_cache.dart';
import '../../reply/data/reply_repository.dart';

/// Today's paid-AI allowance, and the way to clear the reply cache.
///
/// The budget is the app's promise that "free" stays free, so the number is
/// shown rather than hidden until it bites. Reading it also tells the user the
/// truth people usually learn the hard way: the count is per device, not per
/// account.
class AiUsageCard extends ConsumerStatefulWidget {
  const AiUsageCard({super.key});

  @override
  ConsumerState<AiUsageCard> createState() => _AiUsageCardState();
}

class _AiUsageCardState extends ConsumerState<AiUsageCard> {
  AiBudgetSnapshot? _snapshot;
  int _cachedReplies = 0;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final repo = ref.read(replyRepositoryProvider);
    final budget = repo is BudgetedReplyRepository ? repo.budget : null;
    if (!mounted) return;
    setState(() {
      _snapshot = budget?.snapshot();
      _cachedReplies = _cacheLength();
    });
  }

  /// Hive is not initialized in a widget test, and a settings screen that
  /// throws because a cache box is missing would be the exact "a missing
  /// dependency must never break a screen" rule this app applies to Firebase.
  int _cacheLength() {
    try {
      if (!Hive.isBoxOpen(ReplyCache.boxName)) return 0;
      return Hive.box<dynamic>(ReplyCache.boxName).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      if (Hive.isBoxOpen(ReplyCache.boxName)) {
        await Hive.box<dynamic>(ReplyCache.boxName).clear();
      }
    } catch (_) {
      // Nothing to clear if the box never opened.
    }
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _cachedReplies = 0;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Reply cache cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snapshot == null)
              Text(
                'AI usage is not being counted on this install.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                '${snapshot.used} of ${snapshot.limit} AI replies used today',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: snapshot.fraction,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: snapshot.exhausted
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.exhausted
                    ? 'The allowance is used up. It resets tomorrow.'
                    : 'Counting requests, not tokens — this is a per-device '
                          'guard, not a billing system for an AI provider '
                          'account.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cached replies: $_cachedReplies',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cachedReplies == 0 || _clearing
                      ? null
                      : _clearCache,
                  child: Text(_clearing ? 'Clearing…' : 'Clear cache'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
