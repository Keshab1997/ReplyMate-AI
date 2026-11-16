import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/constants/reply_options.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/mascot_face.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../notifications/models/captured_notification.dart';
import '../../notifications/providers/notification_providers.dart';
import '../providers/saved_replies_provider.dart';
import '../data/offline_suggestions.dart';
import '../data/reply_repository.dart';
import '../domain/reply_request.dart';
import '../domain/reply_refinement.dart';
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
    this.offline = false,
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

  /// These came from the on-device rule layer, not a model. Shown plainly: the
  /// app promises never to present something as AI output when it is not.
  final bool offline;

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  AppStrings get _strings => ref.read(appStringsProvider);

  bool _regenerating = false;
  String? _regenerateError;
  late final List<bool> _refining = List<bool>.filled(
    widget.replies.length,
    false,
  );

  Future<void> _refine(
    int index,
    String draft,
    ReplyRefinement refinement,
  ) async {
    setState(() => _refining[index] = true);
    final rewrite = widget.request.copyWith(
      count: 1,
      tone:
          refinement == ReplyRefinement.softer ||
              refinement == ReplyRefinement.politeDecline
          ? ReplyTone.polite
          : widget.request.tone,
      length: refinement == ReplyRefinement.shorter
          ? ReplyLength.short
          : widget.request.length,
      draftToRefine: draft,
      refinementInstruction: refinement.instruction,
    );
    final result = await ref.read(replyRepositoryProvider).generate(rewrite);
    if (!mounted) return;
    setState(() => _refining[index] = false);
    switch (result) {
      case ReplySuccess(:final replies) when replies.isNotEmpty:
        _controllers[index].text = replies.first;
        _controllers[index].selection = TextSelection.collapsed(
          offset: replies.first.length,
        );
      case ReplySuccess():
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_strings.refineFailed)));
      case ReplyFailure(:final message):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// True once the free, on-device variation has been offered for this screen.
  /// One free try, not a loop: the second tap means "I want the model".
  bool _freeVariantShown = false;

  /// The lines the user is looking at right now, edited or not.
  Set<String> get _visibleReplies => <String>{
    for (final controller in _controllers) controller.text.trim(),
  };

  /// Fresh candidates from the rules layer, or nothing when that layer has no
  /// business answering this request.
  ///
  /// Intent chips and writing briefs are left out on purpose: a generic
  /// "Got it." cannot answer "write a romantic quote", and offering one would
  /// be the same dishonesty the offline note exists to avoid.
  List<String> _freeAlternatives() {
    final request = widget.request;
    if (request.replyIntent != null || request.mode == ReplyMode.createMessage) {
      return const <String>[];
    }
    return OfflineSuggestions.forMessage(
      request.trimmedMessage,
      language: request.language,
      tone: request.tone,
      length: request.length,
      count: _controllers.length,
      exclude: _visibleReplies,
    );
  }

  /// "Different one, please" — answered by the rules on this phone.
  ///
  /// This is the cheap half of regenerate: the most common reason people ask
  /// again is "not quite right", and the rules layer can usually phrase the
  /// same intent another way for no tokens, no key and no network. It is a
  /// separate action rather than a silent first step of [Regenerate], because
  /// the cache banner's regenerate means *ask the model* and quietly answering
  /// that with local text would be the kind of small lie this screen avoids.
  ///
  /// The banner it raises offers the escalation, so nobody is trapped in the
  /// free path.
  void _freeVariation() {
    final free = _freeAlternatives();
    if (free.isEmpty) return;
    for (var i = 0; i < _controllers.length && i < free.length; i++) {
      _controllers[i].text = free[i];
    }
    setState(() {
      _freeVariantShown = true;
      _regenerateError = null;
    });
  }

  /// Ask the provider again, bypassing the cache.
  ///
  /// This is the escape hatch the cache is only honest *because* of: without a
  /// real regenerate, "from cache" would be a one-way state and a stale reply
  /// would have no exit.
  Future<void> _regenerateFromProvider() async {
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
        // The fresh set gets its own screen, and this one stays underneath with
        // its controllers intact. They used to be disposed here first, so the
        // write below tickled a disposed TextEditingController - a crash on the
        // one path a user reaches by asking for a better reply.
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

  Future<void> _save(String text) async {
    final saved = await ref.read(savedRepliesProvider.notifier).add(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? _strings.replySaved : _strings.replyNotSaved),
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
          gradient: AppTheme.backgroundGradient(
            theme.brightness,
            primary: theme.colorScheme.primary,
          ),
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

                if (widget.offline) ...[
                  _OfflineNote(),
                  const SizedBox(height: AppTheme.spaceSm),
                ],
                if (widget.cachedAt != null) ...[
                  _CacheBanner(
                    cachedAt: widget.cachedAt!,
                    busy: _regenerating,
                    onRegenerate: _regenerateFromProvider,
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                ],
                if (!_freeVariantShown && _freeAlternatives().isNotEmpty) ...[
                  _FreeVariationOffer(busy: _regenerating, onPressed: _freeVariation),
                  const SizedBox(height: AppTheme.spaceSm),
                ],
                if (_freeVariantShown) ...[
                  _FreeVariantBanner(
                    busy: _regenerating,
                    onAskAi: _regenerateFromProvider,
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
                      color: theme.colorScheme.primary.withValues(
                        alpha: isDark ? 0.12 : 0.07,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.context!.displayTitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
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
                    onRefine: (draft, refinement) =>
                        _refine(index, draft, refinement),
                    onSave: _save,
                    refining: _refining[index],
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

/// The free half of "not quite right": one tap, no provider call.
class _FreeVariationOffer extends StatelessWidget {
  const _FreeVariationOffer({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Not quite right? The rules on this phone can phrase it another '
            'way for free.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: busy ? null : onPressed,
          child: const Text('Free variation'),
        ),
      ],
    );
  }
}

/// Said out loud, every time: this phrasing came from the rules on this phone.
class _FreeVariantBanner extends StatelessWidget {
  const _FreeVariantBanner({required this.busy, required this.onAskAi});

  final bool busy;
  final Future<void> Function() onAskAi;

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
              'Free variation · rewritten on this device, no AI call made',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onAskAi,
            child: const Text('Ask AI'),
          ),
        ],
      ),
    );
  }
}

/// States what these suggestions are, and are not.
class _OfflineNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.offline_bolt_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline suggestions — written on this device from what the '
              'message looks like. No AI call was made, so nothing was sent '
              'anywhere.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
