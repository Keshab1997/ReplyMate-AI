import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../data/chat_reply_style_store.dart';

/// Lets users inspect and delete reply styles they explicitly saved per chat.
class ChatReplyStylesCard extends ConsumerStatefulWidget {
  const ChatReplyStylesCard({super.key});

  @override
  ConsumerState<ChatReplyStylesCard> createState() =>
      _ChatReplyStylesCardState();
}

class _ChatReplyStylesCardState extends ConsumerState<ChatReplyStylesCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The floating composer may save a style in its own Flutter engine.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(chatReplyStylesProvider);
    }
  }

  Future<void> _remove(ChatReplyStyleEntry entry) async {
    await ref.read(chatReplyStyleStoreProvider).remove(entry.key);
    ref.invalidate(chatReplyStylesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(appStringsProvider).chatStyleRemoved(entry.key.contactName),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final styles = ref.watch(chatReplyStylesProvider);
    final theme = Theme.of(context);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spaceMd,
              AppTheme.spaceMd,
              AppTheme.spaceMd,
              AppTheme.spaceSm,
            ),
            child: Text(
              strings.chatStylesPrivacyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          styles.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppTheme.spaceMd),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => _EmptyStyleList(text: strings.noChatStyles),
            data: (entries) => entries.isEmpty
                ? _EmptyStyleList(text: strings.noChatStyles)
                : Column(
                    children: [
                      for (final entry in entries)
                        ListTile(
                          dense: true,
                          title: Text(entry.key.contactName),
                          subtitle: Text(
                            '${entry.key.packageName}\n'
                            '${entry.style.language.label} · '
                            '${entry.style.tone.label} · '
                            '${entry.style.length.label}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: strings.removeChatStyle,
                            onPressed: () => _remove(entry),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStyleList extends StatelessWidget {
  const _EmptyStyleList({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppTheme.spaceMd),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
