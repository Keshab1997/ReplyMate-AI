import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/screen_header.dart';
import '../data/writer_chat_history_store.dart';
import '../providers/writer_chat_history_provider.dart';

class CreateMessageHistoryScreen extends ConsumerStatefulWidget {
  const CreateMessageHistoryScreen({super.key});

  @override
  ConsumerState<CreateMessageHistoryScreen> createState() =>
      _CreateMessageHistoryScreenState();
}

class _CreateMessageHistoryScreenState
    extends ConsumerState<CreateMessageHistoryScreen> {
  /// What the user typed into the search field. Empty means "show everything".
  String _query = '';

  /// A chat matches when the query appears in its first brief (the list title)
  /// or in any of its prompts and drafts.
  ///
  /// Matching the turns and not just the title is the point: the title is the
  /// first line the user happened to type, and the thing they remember is
  /// usually something said later in the chat. Case-insensitive, because a
  /// search box that cares about capitals is a search box people stop using.
  bool _matches(WriterChatHistory chat, String query) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    for (final turn in chat.turns) {
      if (turn.prompt.toLowerCase().contains(needle)) return true;
      for (final reply in turn.replies) {
        if (reply.toLowerCase().contains(needle)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
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
              // Search appears only once there is something to search. A field
              // above an empty list is furniture.
              if (history.valueOrNull?.isNotEmpty ?? false) ...[
                TextField(
                  key: const Key('writerHistorySearch'),
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    hintText: strings.writerHistorySearch,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceSm),
              ],
              Expanded(
                child: history.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(child: Text(strings.noWriterHistory)),
                  data: (items) => items.isEmpty
                      ? Center(child: Text(strings.noWriterHistory))
                      : (() {
                          final visible = items
                              .where((chat) => _matches(chat, _query))
                              .toList(growable: false);
                          if (visible.isEmpty) {
                            return Center(
                              child: Text(
                                strings.writerHistoryNoMatch,
                                key: const Key('writerHistoryNoMatch'),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = visible[index];
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
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  onPressed: () async {
                                    await ref
                                        .read(writerChatHistoryStoreProvider)
                                        .delete(item.id);
                                    ref.invalidate(writerChatHistoryProvider);
                                  },
                                ),
                              );
                            },
                          );
                        })(),
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
