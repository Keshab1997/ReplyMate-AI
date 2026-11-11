import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../models/screen_reading_status.dart';
import '../providers/screen_reading_provider.dart';

/// What the screen reader is actually doing, in words.
///
/// "It does not work" is not a bug report - it is five different failures that
/// look identical from the outside. This card names the one that happened, so
/// the difference between a missing permission, an empty allowlist and a bad
/// read is visible on the phone instead of through adb.
class ScreenReadingStatusCard extends ConsumerWidget {
  const ScreenReadingStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(screenReadingStatusProvider).value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        0,
        AppTheme.spaceMd,
        AppTheme.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'What the reader is doing',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                // The report lives on the native side and changes while the
                // user is in another app, so refreshing is a fresh ask.
                onPressed: () => ref.invalidate(screenReadingStatusProvider),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in _lines(status))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _lines(ScreenReadingStatus? status) {
    if (status == null) return const ['No answer from the native side yet.'];
    return <String>[
      if (!status.connected) 'Service: not running',
      if (!status.enabledByUser) 'Switch: off',
      status.allowlist.isEmpty
          ? 'Watching: nothing selected'
          : 'Watching: ${status.allowlist.join(', ')}',
      'Scans: ${status.scanCount}',
      'Last scan: ${status.summary}',
      // Shown only when something was read: it is the fastest way to see the
      // reader picked the wrong bubble.
      if (status.lastText != null) 'Seen: "${status.lastText}"',
    ];
  }
}
