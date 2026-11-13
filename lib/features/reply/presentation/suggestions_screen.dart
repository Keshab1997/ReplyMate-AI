import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/mascot_face.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../notifications/models/captured_notification.dart';
import '../../notifications/providers/notification_providers.dart';
import '../data/reply_repository.dart';
import '../domain/reply_request.dart';
import 'widgets/suggestion_card.dart';

/// Screen 7 of: generated replies as separate
/// cards with copy, edit and - only when a valid RemoteInput action exists -
/// quick reply (FR-08, USER_FLOWS flows 2 and 3).
class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({
    required this.replies,
    required this.request,
    this.context,
    this.cachedAt,
    super.key,
  });

  final List<String> replies;
  final ReplyRequest request;
  final CapturedNotification? context;

  /// Set when these replies came from the on-device cache instead of a paid
  /// call. Shown as a quiet banner with a real regenerate: the text is the
  /// same, but "this cost nothing and is a few days old" is something the user
  /// is entitled to know before sending it.
  final DateTime? cachedAt;

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  AppStrings get _strings => ref.read(appStringsProvider);

  bool _regenerating = false;
  String? _regenerateError;

  /// Ask again, bypassing the cache.
  ///
  /// This is the escape hatch the cache is only honest *because* of: without a
  /// real regenerate, "from cache" would be a one-way state and a stale reply
  /// would have no exit.
  Future<void> _regenerate() async {
    setState(() {
      _regenerating = true;
      _regenerateError = null;
    });
    final result = await ref
        .read(replyRepositoryProvider)
        .generate(widget.request, bypassCache: true);
    if (!mounted) return;
    setState(() => _regenerating = false);
    switch (result) {
      case ReplySuccess(:final replies):
        for (final controller in _controllers) {
          controller.dispose();
        }
        setState(() {
          for (var i = 0; i < replies.length; i++) {
            if (i < _controllers.length) {
              _controllers[i].text = replies[i];
            }
          }
        });
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuggestionsScreen(
              replies: replies,
              request: widget.request,
              context: widget.context,
            ),
          ),
        );
      case ReplyFailure(:final message):
        setState(() => _regenerateError = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
    }
  }

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

                if (widget.cachedAt != null) ...[
                  _CacheBanner(
                    cachedAt: widget.cachedAt!,
                    busy: _regenerating,
                    onRegenerate: _regenerate,
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                ],
                if (_regenerateError != null) ...[
                  Text(
                    _regenerateError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                ],

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

/// A quiet, honest line: these replies cost nothing and are not fresh.
class _CacheBanner extends StatelessWidget {
  const _CacheBanner({
    required this.cachedAt,
    required this.busy,
    required this.onRegenerate,
  });

  final DateTime cachedAt;
  final bool busy;
  final Future<void> Function() onRegenerate;

  String _age() {
    final diff = DateTime.now().difference(cachedAt);
    if (diff.inMinutes < 1) return 'moments';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    return '${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'From cache · ${_age()} ago · no AI call was made',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onRegenerate, child: const Text('Regenerate')),
        ],
      ),
    );
  }
}
