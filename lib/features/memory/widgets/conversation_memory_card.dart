import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/conversation_memory.dart';
import '../providers/conversation_memory_provider.dart';

/// The consent surface for conversation memory (docs/CONVERSATION_MEMORY.md §3).
///
/// This card is the feature's first wall made visible: the switch starts off,
/// the copy says in plain words what is stored and where, and everything stored
/// is listed here by name so it can be deleted one line at a time. A memory the
/// user cannot see is not a memory they consented to - it is a leak with a
/// toggle.
class ConversationMemoryCard extends ConsumerStatefulWidget {
  const ConversationMemoryCard({super.key});

  @override
  ConsumerState<ConversationMemoryCard> createState() =>
      _ConversationMemoryCardState();
}

class _ConversationMemoryCardState
    extends ConsumerState<ConversationMemoryCard> {
  List<ConversationKey>? _contacts;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final controller = ref.read(conversationMemoryControllerProvider);
    final contacts = await controller.contacts();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    await ref
        .read(conversationMemoryEnabledProvider.notifier)
        .setEnabled(enabled);
    if (!mounted) return;
    // Switching on starts empty and switching off deletes, so the list is
    // re-read either way rather than patched.
    setState(() => _loading = true);
    await _refresh();
  }

  Future<void> _forget(ConversationKey key) async {
    await ref.read(conversationMemoryControllerProvider).forget(key);
    if (!mounted) return;
    setState(() => _loading = true);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Forgot the conversation with ${key.contactName}.'),
      ),
    );
  }

  Future<void> _forgetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all remembered chats?'),
        content: const Text(
          'Every message this app remembered is deleted from this device. The '
          'replies are not affected - only what the app kept to write them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(conversationMemoryControllerProvider).forgetAll();
    if (!mounted) return;
    setState(() => _loading = true);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(conversationMemoryEnabledProvider);
    final contacts = _contacts ?? const <ConversationKey>[];

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: _setEnabled,
            title: const Text('Remember recent chats'),
            subtitle: const Text(
              'Keeps the last few messages of each chat - and replies you '
              'accept - so the next draft follows the conversation and sounds '
              'like you. Stored on this device only, never uploaded, and never '
              'in a backup. Off by default; turning it off deletes everything '
              'it kept.',
            ),
          ),
          if (enabled) ...[
            const Divider(height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppTheme.spaceMd),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Nothing remembered yet. Open a reply for a chat and it '
                    'will show up here.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              )
            else ...[
              for (final key in contacts)
                ListTile(
                  dense: true,
                  title: Text(key.contactName),
                  subtitle: Text(key.packageName),
                  trailing: IconButton(
                    tooltip: 'Forget this chat',
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _forgetAll,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Delete all remembered chats'),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
