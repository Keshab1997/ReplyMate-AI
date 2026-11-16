import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/screen_header.dart';
import '../data/writer_chat_history_store.dart';
import '../providers/writer_chat_history_provider.dart';

class CreateMessageHistoryScreen extends ConsumerWidget {
  const CreateMessageHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final history = ref.watch(writerChatHistoryProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            children: [
              ScreenHeader(title: strings.writerHistory),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                strings.writerHistoryPrivacyNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Expanded(
                child: history.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(child: Text(strings.noWriterHistory)),
                  data: (items) => items.isEmpty
                      ? Center(child: Text(strings.noWriterHistory))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              key: ValueKey<String>(
                                'writer-history-${item.id}',
                              ),
                              title: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${strings.writerHistoryTurnCount(item.turns.length)} · ${_dateLabel(item.updatedAt)}',
                              ),
                              onTap: () => Navigator.of(context).pop(item),
                              trailing: IconButton(
                                key: ValueKey<String>(
                                  'delete-writer-history-${item.id}',
                                ),
                                tooltip: strings.deleteWriterChat,
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () async {
                                  await ref
                                      .read(writerChatHistoryStoreProvider)
                                      .delete(item.id);
                                  ref.invalidate(writerChatHistoryProvider);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }
}
