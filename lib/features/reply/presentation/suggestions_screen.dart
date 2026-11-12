import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/mascot_face.dart';
import '../../../shared/widgets/screen_header.dart';
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
  AppStrings get _strings => ref.read(appStringsProvider);

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
        .showSnackBar(SnackBar(content: Text(_strings.replyCopied)));
  }

  /// Shares the edited suggestion through Android's chooser. Opening the
  /// chooser is not the same as sending: the user selects an app and confirms.
  Future<void> _share(String text) async {
    final opened = await ref.read(notificationsBridgeProvider).shareText(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened ? _strings.shareOpened : _strings.shareUnavailable,
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
          child: AppSurfaces.centered(
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                AppTheme.spaceSm,
                AppTheme.spaceMd,
                AppTheme.spaceXl,
              ),
              children: [
                ScreenHeader(
                  title: count == 1
                      ? _strings.oneWayToSayIt
                      : '$count ways to say it',
                  subtitle:
                      '${widget.request.language.label} · '
                      '${widget.request.tone.label} · '
                      '${widget.request.length.label}',
                  // The helper is happy: the work is done. The replies remain
                  // the visual focus, so the face stays small.
                  trailing: const MascotFace(
                    size: 36,
                    mood: MascotMood.happy,
                    glow: false,
                  ),
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
                              ? _strings.noTextVisible
                              : widget.context!.displayText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13.5,
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
                    strings: _strings,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                ],

                const SizedBox(height: AppTheme.spaceMd),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_strings.generateAgain),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
