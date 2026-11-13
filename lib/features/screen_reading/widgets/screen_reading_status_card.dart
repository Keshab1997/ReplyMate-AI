import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../notifications/providers/notification_providers.dart';
import '../models/screen_reading_status.dart';
import '../providers/screen_reading_provider.dart';
import '../../../core/l10n/app_strings.dart';

/// What the screen reader is actually doing, in words - and, when it is not
/// working, the way to the one screen that can fix it.
/// "It does not work" is not a bug report: it is five different failures that
/// look identical from the outside. This card names the one that happened, so
/// the difference between a missing permission, an empty allowlist and a bad
/// read is visible on the phone instead of through adb on a laptop.
class ScreenReadingStatusCard extends ConsumerWidget {
  const ScreenReadingStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strings = ref.watch(appStringsProvider);
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
                  strings.readerWhatDoing,
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
                label: Text(strings.readerRefresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in _lines(strings, status))
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
          // Offered exactly when the reader is not working: this is the button
          // that turns "it does not work" into one tap on the right toggle.
          if (status == null || status.needsAttention) ...[
            const SizedBox(height: AppTheme.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openAndroidSettings(context, ref, strings),
                icon: const Icon(Icons.settings_applications_outlined),
                label: Text(strings.readerOpenSettings),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAndroidSettings(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final opened = await ref
        .read(notificationsBridgeProvider)
        .openAccessibilitySettings();
    if (!context.mounted) return;
    if (opened == 'none') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.readerNoAccessibility)));
    }
  }

  List<String> _lines(AppStrings strings, ScreenReadingStatus? status) {
    if (status == null) return [strings.readerNoAnswer];
    return <String>[
      if (!status.connected) strings.readerServiceStopped,
      if (!status.enabledByUser) strings.readerSwitchOff,
      status.allowlist.isEmpty
          ? strings.readerWatchingNothing
          : strings.readerWatching(status.allowlist.join(', ')),
      strings.readerScans(status.scanCount),
      strings.readerLastScan(status.summary),
      // The one case where the advice is not a setting: the reader is fine and
      // has simply never been shown a conversation.
      if (!status.hasScanned) strings.readerNothingYet,
      // Shown only when something was read: it is the fastest way to see the
      // reader picked the wrong bubble.
      if (status.lastText != null) strings.readerSeen(status.lastText!),
    ];
  }
}
