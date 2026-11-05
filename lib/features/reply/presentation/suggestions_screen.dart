import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../notifications/models/captured_notification.dart';
import '../../notifications/providers/notification_providers.dart';
import '../domain/reply_request.dart';
import 'widgets/suggestion_card.dart';

/// Screen 7 of docs/SCREEN_SPECIFICATIONS.md: generated replies as separate
/// cards with copy, edit and - only when a valid RemoteInput action exists -
/// quick reply (FR-08, USER_FLOWS flows 2 and 3).
class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({
    required this.replies,
    required this.request,
    this.context,
    super.key,
  });

  final List<String> replies;
  final ReplyRequest request;
  final CapturedNotification? context;

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  late final List<TextEditingController> _controllers = [
    for (final reply in widget.replies) TextEditingController(text: reply),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Reply copied.')));
  }

  /// Quick reply is attempted only against a notification that exposed a
  /// valid action; every failure falls back to copy / open-app with an
  /// honest explanation instead of pretending it worked.
  Future<void> _quickReply(String text) async {
    final notification = widget.context;
    if (notification == null || !notification.hasReplyAction) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quick reply is unavailable for this message. '
            'Copy the reply and paste it in the app instead.',
          ),
        ),
      );
      return;
    }
    final sent = await ref
        .read(notificationsBridgeProvider)
        .sendQuickReply(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Reply handed to ${notification.displayTitle}.'
              : 'The reply action is no longer valid. '
                    'Copy the reply and paste it in the app instead.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickReplyAvailable = widget.context?.hasReplyAction ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Suggestions')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          children: [
            Row(
              children: [
                Text(
                  '${widget.request.language.label} · '
                  '${widget.request.tone.label} tone',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Change'),
                ),
              ],
            ),
            for (var index = 0; index < widget.replies.length; index++) ...[
              SuggestionCard(
                controller: _controllers[index],
                quickReplyAvailable: quickReplyAvailable,
                onCopy: _copy,
                onQuickReply: _quickReply,
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(
                      child: Text(
                        quickReplyAvailable
                            ? 'Quick reply sends through the app\'s own '
                                  'notification action. You stay in control.'
                            : 'Quick reply works only in apps that support '
                                  'it. Otherwise copy the reply.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Generate again'),
            ),
          ],
        ),
      ),
    );
  }
}
