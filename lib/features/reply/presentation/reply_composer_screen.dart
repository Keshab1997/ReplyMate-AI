import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/choice_chips.dart';
import '../../../shared/widgets/mascot_face.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../memory/providers/conversation_memory_provider.dart';
import '../../notifications/models/captured_notification.dart';
import '../../notifications/models/launch_context.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../settings/providers/preferences_provider.dart';
import '../data/reply_repository.dart';
import '../domain/reply_request.dart';
import 'suggestions_screen.dart';

/// Screen 6 of docs/SCREEN_SPECIFICATIONS.md. Context arrives from one of
/// four user-initiated routes: a captured notification, the text-selection
/// action, the share sheet, or plain paste/type (FR-04, FR-08).
class ReplyComposerScreen extends ConsumerStatefulWidget {
  const ReplyComposerScreen({
    this.initialNotification,
    this.embedded = false,
    super.key,
  });

  /// Context handed in directly, for a launch that already consumed it: the
  /// fallback notification path opens this screen with the message prefilled
  /// instead of relying on the in-memory capture buffer
  /// (docs/FLOATING_OVERLAY.md §4.3).
  final CapturedNotification? initialNotification;

  /// See `HomeScreen.embedded`. When true the BackButton is dropped as well:
  /// this screen is a tab then, and a back arrow would pop the whole shell.
  final bool embedded;

  @override
  ConsumerState<ReplyComposerScreen> createState() =>
      _ReplyComposerScreenState();
}

class _ReplyComposerScreenState extends ConsumerState<ReplyComposerScreen> {
  AppStrings get _strings => ref.read(appStringsProvider);

  /// Shown when the session has no context at all: no captured notification,
  /// no launch text. Silence is the symptom users report ("nothing happened"),
  /// so the composer says why the box is empty instead of looking broken
  /// (docs/OVERLAY_TASKS.md, Batch 0). The wording lives in [AppStrings] so a
  /// Bengali or Hindi session gets it in its own language.

  final TextEditingController _messageController = TextEditingController();

  ReplyLanguage _language = ReplyLanguage.english;
  ReplyTone _tone = ReplyTone.friendly;
  ReplyLength _length = ReplyLength.short;
  int _count = AppConstants.defaultSuggestionCount;

  CapturedNotification? _context;
  bool _initialised = false;
  bool _generating = false;
  ReplyFailure? _failure;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// One-time setup: defaults from preferences, context from the launch
  /// intent (PROCESS_TEXT / SEND) or the newest captured notification.
  ///
  /// Runs inside build *without* setState: the values assigned here are read
  /// by the same frame, and calling setState during build is an error. It
  /// waits until the one-shot launch-context read has resolved so that text
  /// arriving through an intent is never dropped.
  void _initialise(
    ReplyPreferences preferences,
    LaunchContext? launch, {
    required bool launchResolved,
  }) {
    if (_initialised || !launchResolved) return;
    _initialised = true;
    _language = preferences.language;
    _tone = preferences.tone;
    _length = preferences.length;
    final captured = ref.read(capturedNotificationsProvider);
    if (launch != null && launch.hasText) {
      _messageController.text = launch.text;
    } else if (widget.initialNotification != null) {
      // The reason this screen opened outranks a stale buffer.
      _context = widget.initialNotification;
      _messageController.text = widget.initialNotification!.displayText;
    } else if (captured.isNotEmpty) {
      _context = captured.first;
      _messageController.text = captured.first.displayText;
    }
  }

  Future<void> _generate() async {
    // Same memory contract as the bubble: file the message, then draft from the
    // window that includes it. Null here means memory is off or does not apply,
    // and the capture's own history is used instead.
    final capture = _context;
    final memory = capture == null
        ? null
        : await ref
              .read(conversationMemoryControllerProvider)
              .rememberCapture(capture);
    if (!mounted) return;
    final request = ReplyRequest(
      message: _messageController.text,
      language: _language,
      tone: _tone,
      length: _length,
      count: _count,
      priorMessages:
          memory?.contextLines() ?? capture?.priorMessages ?? const <String>[],
      styleExamples: memory?.styleExamples() ?? const <String>[],
    );
    final problems = request.validate();
    if (problems.isNotEmpty) {
      setState(() => _failure = ReplyFailure(problems.join(' ')));
      return;
    }
    setState(() {
      _generating = true;
      _failure = null;
    });
    final result = await ref.read(replyRepositoryProvider).generate(request);
    if (!mounted) return;
    setState(() => _generating = false);
    switch (result) {
      case ReplySuccess(:final replies):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuggestionsScreen(
              replies: replies,
              request: request,
              context: _context,
            ),
          ),
        );
      case ReplyFailure(:final message, :final isRetryable):
        setState(
          () => _failure = ReplyFailure(message, isRetryable: isRetryable),
        );
    }
  }

  void _clearSessionContext() {
    ref.read(capturedNotificationsProvider.notifier).clear();
    unawaited(ref.read(notificationsBridgeProvider).clearRetainedContext());
    _messageController.clear();
    _context = null;
  }

  @override
  Widget build(BuildContext context) {
    final launchState = ref.watch(launchContextProvider);
    final preferences = ref.watch(preferencesProvider);
    final captured = ref.watch(capturedNotificationsProvider);
    _initialise(
      preferences,
      launchState.value,
      launchResolved: launchState.hasValue,
    );
    final launch = launchState.value;

    final theme = Theme.of(context);

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _clearSessionContext();
      },
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.backgroundGradient(theme.brightness),
          ),
          child: SafeArea(
            bottom: !widget.embedded,
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
                    title: _strings.newReply,
                    showBack: !widget.embedded,
                    // Listening while the user writes, thinking while the
                    // request is in flight - one face, two truthful states.
                    trailing: MascotFace(
                      size: 36,
                      glow: false,
                      animate: false,
                      mood: _generating
                          ? MascotMood.thinking
                          : MascotMood.listening,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),

                  // Message first: without it there is nothing to answer, so it
                  // gets the biggest surface on the screen.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _strings.messageLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              if (_context != null)
                                TextButton.icon(
                                  onPressed: () =>
                                      setState(_clearSessionContext),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                  ),
                                  label: Text(_strings.clear),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 30),
                                    textStyle: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          if (_context != null) ...[
                            Text(
                              _context!.displayTitle,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandBright,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (_context!.contextWarnings.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  _context!.contextWarnings.join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (captured.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppTheme.spaceSm,
                                ),
                                child: DropdownButton<CapturedNotification>(
                                  isExpanded: true,
                                  value: _context,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final notification in captured)
                                      DropdownMenuItem(
                                        value: notification,
                                        child: Text(
                                          notification.hasText
                                              ? notification.displayText
                                              : '(no text) '
                                                    '${notification.displayTitle}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _context = value;
                                      _messageController.text =
                                          value?.displayText ?? '';
                                    });
                                  },
                                ),
                              ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                // Context-less session: say so. A blank field
                                // with no explanation reads as a broken app;
                                // this reads as a state the user can act on.
                                launch != null && launch.hasText
                                    ? _strings.fromSource(
                                        launch.source.label.toLowerCase(),
                                      )
                                    : _strings.noMessageCaptured,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  height: 1.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          TextField(
                            controller: _messageController,
                            minLines: 3,
                            maxLines: 8,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 1.5,
                            ),
                            decoration: InputDecoration(
                              hintText: _strings.messageTextHint,
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            onChanged: (_) => setState(() => _failure = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),

                  // One card for the three axes, because they are one decision:
                  // how the reply should sound.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StyleLabel(_strings.languageLabel),
                          ChoiceChips<ReplyLanguage>(
                            options: ReplyLanguage.values,
                            selected: _language,
                            labelOf: (language) => language.label,
                            iconOf: (_) => AppIcons.language,
                            onSelected: (language) =>
                                setState(() => _language = language),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          _StyleLabel('Tone'),
                          ChoiceChips<ReplyTone>(
                            options: ReplyTone.values,
                            selected: _tone,
                            labelOf: (tone) => tone.label,
                            iconOf: (_) => AppIcons.tone,
                            onSelected: (tone) => setState(() => _tone = tone),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          _StyleLabel(_strings.lengthLabel),
                          ChoiceChips<ReplyLength>(
                            options: ReplyLength.values,
                            selected: _length,
                            labelOf: (length) => length.label,
                            iconOf: (_) => AppIcons.length,
                            onSelected: (length) =>
                                setState(() => _length = length),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          _StyleLabel(_strings.howManyOptions),
                          ChoiceChips<int>(
                            options: List<int>.generate(
                              AppConstants.maxSuggestionCount -
                                  AppConstants.minSuggestionCount +
                                  1,
                              (index) =>
                                  AppConstants.minSuggestionCount + index,
                            ),
                            selected: _count,
                            labelOf: (count) => '$count',
                            iconOf: (_) => AppIcons.count,
                            onSelected: (count) {
                              setState(() => _count = count);
                              ref
                                  .read(preferencesProvider.notifier)
                                  .setSuggestionCount(count);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_failure != null) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 17,
                            color: AppTheme.danger,
                          ),
                          const SizedBox(width: AppTheme.spaceSm),
                          Expanded(
                            child: Text(
                              _failure!.message,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppTheme.spaceLg),
                  AppSurfaces.primaryAction(
                    context,
                    onPressed: _generating ? null : _generate,
                    icon: _generating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : const Icon(AppIcons.generate, size: 19),
                    label: _generating
                        ? _strings.generating
                        : _strings.generateSuggestions,
                  ),
                  if (_generating) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    const _SuggestionsSkeleton(),
                  ],
                  const SizedBox(height: AppTheme.spaceSm),
                  Center(
                    child: Text(
                      _strings.sentOnlyOnGenerate,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A lightweight preview of the suggestion layout while the request runs.
/// It animates in once, rather than keeping an indefinite shimmer alive.
class _SuggestionsSkeleton extends StatelessWidget {
  const _SuggestionsSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.55 : 0.8,
    );
    Widget line(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(0.32, 12),
              const SizedBox(height: AppTheme.spaceMd - 4),
              line(0.94, 14),
              const SizedBox(height: AppTheme.spaceSm),
              line(0.78, 14),
              const SizedBox(height: AppTheme.spaceSm),
              line(0.48, 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny label above a chip row.
class _StyleLabel extends StatelessWidget {
  const _StyleLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
