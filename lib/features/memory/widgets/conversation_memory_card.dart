import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../domain/conversation_memory.dart';
import '../providers/conversation_memory_provider.dart';

/// The consent surface for conversation memory (docs/CONVERSATION_MEMORY.md §3).
///
/// This card is the feature's first wall made visible: the switch starts off,
/// the copy says in plain words what is stored and where, and everything stored
/// is listed here by name so it can be deleted one line at a time. A memory the
/// user cannot see is not a memory they consented to - it is a leak with a
/// toggle.
///
/// The list reads a provider, not a `initState` snapshot: the shell keeps
/// Settings alive in an `IndexedStack`, so a one-off read would keep showing
/// "nothing remembered yet" long after something was remembered. A device found
/// that, which is exactly the kind of bug this card exists to make impossible.
class ConversationMemoryCard extends ConsumerStatefulWidget {
  const ConversationMemoryCard({super.key});

  @override
  ConsumerState<ConversationMemoryCard> createState() =>
      _ConversationMemoryCardState();
}

class _ConversationMemoryCardState extends ConsumerState<ConversationMemoryCard>
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
    // Drafts are generated in the bubble, which runs in its own Flutter engine,
    // so its writes cannot invalidate anything here. Coming back to the app is
    // the moment the list can honestly catch up.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(conversationMemoryContactsProvider);
    }
  }

  AppStrings get _strings => ref.read(appStringsProvider);

  Future<void> _setEnabled(bool enabled) async {
    await ref
        .read(conversationMemoryEnabledProvider.notifier)
        .setEnabled(enabled);
    if (!mounted) return;
    ref.invalidate(conversationMemoryContactsProvider);
  }

  Future<void> _forget(ConversationKey key) async {
    await ref.read(conversationMemoryControllerProvider).forget(key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_strings.forgotConversation(key.contactName))),
    );
  }

  Future<void> _forgetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_strings.deleteAllTitle),
        content: Text(_strings.deleteAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_strings.keep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(conversationMemoryControllerProvider).forgetAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(conversationMemoryEnabledProvider);
    final contacts = ref.watch(conversationMemoryContactsProvider);

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: _setEnabled,
            title: Text(_strings.rememberRecentChats),
            subtitle: Text(_strings.rememberRecentChatsBody),
          ),
          if (enabled) ...[
            const Divider(height: 1),
            contacts.when(
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
              // A store that cannot be read is not an error to shout about: the
              // honest statement is that nothing could be listed.
              error: (_, _) =>
                  _Empty(theme: theme, text: _strings.nothingRememberedYet),
              data: (keys) => keys.isEmpty
                  ? _Empty(theme: theme, text: _strings.nothingRememberedYet)
                  : Column(
                      children: [
                        for (final key in keys)
                          ListTile(
                            dense: true,
                            title: Text(key.contactName),
                            subtitle: Text(key.packageName),
                            trailing: IconButton(
                              tooltip: _strings.forgetThisChat,
                              onPressed: () => _forget(key),
                              icon: const Icon(Icons.delete_outline, size: 20),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spaceMd,
                            0,
                            AppTheme.spaceMd,
                            AppTheme.spaceMd,
                          ),
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _forgetAll,
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                ),
                                label: Text(_strings.deleteAllRemembered),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: _strings.refresh,
                                onPressed: () => ref.invalidate(
                                  conversationMemoryContactsProvider,
                                ),
                                icon: const Icon(Icons.refresh, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.theme, required this.text});

  final ThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppTheme.spaceMd),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: theme.textTheme.bodySmall),
    ),
  );
}
