import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../reply/data/ai_usage_tracker.dart';
import '../../reply/data/reply_cache.dart';
import '../../reply/data/reply_repository.dart';

/// Informational AI request count and the way to clear the reply cache.
///
/// This local count is not a daily limit or a provider billing meter; it helps
/// the user see their own activity without blocking a request.
class AiUsageCard extends ConsumerStatefulWidget {
  const AiUsageCard({super.key});

  @override
  ConsumerState<AiUsageCard> createState() => _AiUsageCardState();
}

class _AiUsageCardState extends ConsumerState<AiUsageCard> {
  AiUsageSnapshot? _snapshot;
  int _cachedReplies = 0;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final repo = ref.read(replyRepositoryProvider);
    final tracker = repo is CachedReplyRepository ? repo.usageTracker : null;
    if (!mounted) return;
    setState(() {
      _snapshot = tracker?.snapshot();
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
                '${snapshot.used} AI generation attempts today',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Informational local count only — there is no daily app cap. '
                'Your AI provider may still apply its own billing and rate limits.',
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
