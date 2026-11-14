import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/app_strings.dart';
import '../providers/saved_replies_provider.dart';

/// A small settings manager for phrases the user chooses to save. No captured
/// notification or generated reply is ever added without an explicit action.
class SavedRepliesCard extends ConsumerWidget {
  const SavedRepliesCard({super.key});

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.addSavedReply),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(hintText: strings.messageTextHint),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.close),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(strings.addSavedReply),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    await ref.read(savedRepliesProvider.notifier).add(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(savedRepliesProvider);
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            if (replies.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    strings.noSavedReplies,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (final reply in replies)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    reply,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: strings.deleteSavedReply,
                    onPressed: () =>
                        ref.read(savedRepliesProvider.notifier).remove(reply),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                  strings.savedRepliesPrivacyNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _add(context, ref, strings),
                icon: const Icon(Icons.add_rounded),
                label: Text(strings.addSavedReply),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
