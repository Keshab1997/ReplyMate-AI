import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/mascot_face.dart';
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

  /// Shares the edited suggestion through Android's chooser. Opening the
  /// chooser is not the same as sending: the user selects an app and confirms.
  Future<void> _share(String text) async {
    final opened = await ref.read(notificationsBridgeProvider).shareText(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Share sheet opened. Choose an app to continue.'
              : 'Sharing is unavailable here. Copy the reply instead.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final count = widget.replies.length;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spaceMd,
              AppTheme.spaceSm,
              AppTheme.spaceMd,
              AppTheme.spaceXl,
            ),
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 19),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count == 1
                              ? 'One way to say it'
                              : '$count ways to say it',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.request.language.label} · '
                          '${widget.request.tone.label} · '
                          '${widget.request.length.label}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The helper is happy: the work is done. It stays small so
                  // the replies, not the mascot, are what the user reads.
                  MascotFace(size: 34, mood: MascotMood.happy, glow: false),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),

              // What we are answering, quoted, so the user never has to
              // remember or scroll back to check it.
              if (widget.context != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(
                      alpha: isDark ? 0.12 : 0.07,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(color: AppTheme.brand, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.context!.displayTitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.brandBright,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.context!.displayText.isEmpty
                            ? 'No message text was visible in the notification.'
                            : widget.context!.displayText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppTheme.spaceMd),

              for (var index = 0; index < widget.replies.length; index++) ...[
                SuggestionCard(
                  controller: _controllers[index],
                  best: index == 0 && count > 1,
                  onCopy: _copy,
                  onShare: _share,
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],

              const SizedBox(height: AppTheme.spaceMd),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Generate again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
