import 'dart:async';

import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/mascot_face.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../memory/providers/conversation_memory_provider.dart';
import '../../notifications/models/captured_notification.dart';
import '../../notifications/models/launch_context.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../settings/providers/preferences_provider.dart';
import '../data/offline_suggestions.dart';
import '../data/reply_language_detector.dart';
import '../data/reply_repository.dart';
import '../domain/reply_request.dart';
import '../providers/saved_replies_provider.dart';
import 'reply_style_sheet.dart';
import 'suggestions_screen.dart';

/// Screen 6 of. Context arrives from one of
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
  /// The wording lives in [AppStrings] so a
  /// Bengali or Hindi session gets it in its own language.

  final TextEditingController _messageController = TextEditingController();

  ReplyLanguage _language = ReplyLanguage.english;
  ReplyTone _tone = ReplyTone.friendly;
  ReplyLength _length = ReplyLength.short;
  int _count = AppConstants.defaultSuggestionCount;
  bool _languageManuallySelected = false;

  CapturedNotification? _context;
  bool _initialised = false;
  bool _generating = false;
  ReplyFailure? _failure;

  /// The drafts currently on screen. They live here, not on a pushed screen:
  /// the reply is the point, so it appears in the conversation it answers.
  List<String> _suggestions = const <String>[];
  bool _cached = false;
  bool _offline = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// One-time setup: defaults from preferences, context from the launch
  /// intent (PROCESS_TEXT / SEND) or the newest captured notification.
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
    _language =
        ReplyLanguageDetector.detect(_messageController.text) ??
        preferences.language;
  }

  void _messageChanged() {
    final detected = ReplyLanguageDetector.detect(_messageController.text);
    setState(() {
      _failure = null;
      if (!_languageManuallySelected && detected != null) {
        _language = detected;
      }
    });
  }

  ReplyRequest _localReplyRequest() => ReplyRequest(
    message: _messageController.text,
    language: _language,
    tone: _tone,
    length: _length,
    count: 1,
    priorMessages: _context?.priorMessages ?? const <String>[],
  );

  Future<void> _openLocalReply(String reply) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SuggestionsScreen(
        replies: [reply],
        request: _localReplyRequest(),
        context: _context,
        offline: true,
      ),
    ),
  );

  Future<void> _openSavedReplies(List<String> templates) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final template in templates)
              ListTile(
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text(
                  template,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, template),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await _openLocalReply(selected);
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
      _suggestions = const <String>[];
    });
    final result = await ref.read(replyRepositoryProvider).generate(request);
    if (!mounted) return;
    setState(() => _generating = false);
    switch (result) {
      case ReplySuccess(:final replies, :final fromCache, :final offline):
        setState(() {
          _suggestions = replies;
          _cached = fromCache;
          _offline = offline;
        });
      case ReplyFailure(:final message, :final isRetryable):
        setState(
          () => _failure = ReplyFailure(message, isRetryable: isRetryable),
        );
    }
  }

  Future<void> _copyDraft(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_strings.replyCopied)));
  }

  /// Shares the draft through Android's chooser. Opening the chooser is not
  /// sending: the user picks the app and confirms there.
  Future<void> _shareDraft(String text) async {
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

  Future<void> _saveDraft(String text) async {
    final saved = await ref.read(savedRepliesProvider.notifier).add(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? _strings.replySaved : _strings.replyNotSaved),
      ),
    );
  }

  /// Editing a draft happens in the sheet it already lives in, then the result
  /// replaces the draft - so "edit" never silently drops the other two.
  Future<void> _editDraft(int index) async {
    final controller = TextEditingController(text: _suggestions[index]);
    final edited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spaceMd,
              0,
              AppTheme.spaceMd,
              AppTheme.spaceMd,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 10,
                  decoration: InputDecoration(hintText: _strings.replyHint),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                AppSurfaces.primaryAction(
                  sheetContext,
                  label: _strings.done,
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(controller.text.trim()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (edited == null || edited.isEmpty || !mounted) return;
    setState(() {
      final next = List<String>.from(_suggestions);
      next[index] = edited;
      _suggestions = next;
    });
  }

  void _clearSessionContext() {
    ref.read(capturedNotificationsProvider.notifier).clear();
    unawaited(ref.read(notificationsBridgeProvider).clearRetainedContext());
    _messageController.clear();
    _context = null;
  }

  /// Present the style in one tap, and keep the composer's copy in step.
  Future<void> _editStyle() async {
    final choice = await ReplyStyleSheet.show(
      context,
      strings: _strings,
      language: _language,
      tone: _tone,
      length: _length,
      count: _count,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _language = choice.language;
      _tone = choice.tone;
      _length = choice.length;
      _count = choice.count;
      // A manual choice outranks what the detector thinks the text is written
      // in - that is the whole point of choosing it.
      _languageManuallySelected = true;
    });
    await ref
        .read(preferencesProvider.notifier)
        .setSuggestionCount(choice.count);
  }

  @override
  Widget build(BuildContext context) {
    final launchState = ref.watch(launchContextProvider);
    final preferences = ref.watch(preferencesProvider);
    final captured = ref.watch(capturedNotificationsProvider);
    final savedReplies = ref.watch(savedRepliesProvider);
    _initialise(
      preferences,
      launchState.value,
      launchResolved: launchState.hasValue,
    );
    final launch = launchState.value;
    final hasKnownIntent =
        OfflineSuggestions.intentOf(_messageController.text) !=
        OfflineIntent.unknown;
    final quickReplies = hasKnownIntent
        ? OfflineSuggestions.forMessage(
            _messageController.text,
            language: _language,
            tone: _tone,
            length: _length,
            count: 2,
          ).toSet().toList()
        : const <String>[];

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _clearSessionContext();
      },
      child: Scaffold(
        // Transparent chrome: the gesture-aware body below extends to the edges
        // and owns both insets itself.
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.backgroundGradient(theme.brightness),
          ),
          child: Builder(
            builder: (context) {
              // The message and the draft share one scroll view; the style row
              // and the send bar are pinned, the way a chat screen behaves.
              // This is what the Reply tab was missing: every control on the
              // screen used to scroll away together, leaving a form.
              Widget composer = Column(
                children: [
                  Expanded(
                    child: AppSurfaces.centered(
                      ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spaceMd,
                          AppTheme.spaceSm,
                          AppTheme.spaceMd,
                          AppTheme.spaceMd,
                        ),
                        children: [
                          ScreenHeader(
                            title: _strings.newReply,
                            showBack: !widget.embedded,
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
                          ..._buildMessageBubble(
                            context,
                            theme: theme,
                            scheme: scheme,
                            launch: launch,
                            captured: captured,
                          ),
                          if (quickReplies.isNotEmpty) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            _buildQuickReplies(theme, quickReplies),
                          ],
                          if (savedReplies.isNotEmpty) ...[
                            const SizedBox(height: AppTheme.spaceSm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _openSavedReplies(savedReplies),
                                icon: const Icon(
                                  Icons.bookmark_outline_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  '${_strings.savedReplies} '
                                  '(${savedReplies.length})',
                                ),
                              ),
                            ),
                          ],
                          if (_failure != null) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            _buildFailure(theme),
                          ],
                          if (_suggestions.isNotEmpty || _generating) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            ..._buildReplyBubbles(context, theme, scheme),
                          ],
                          // Only once there is something to answer: with an
                          // empty box the line above already explains why, and
                          // two explanations on one screen read as clutter.
                          if (_suggestions.isEmpty &&
                              !_generating &&
                              _failure == null &&
                              _messageController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: AppTheme.spaceLg),
                            _EmptyHint(theme: theme, strings: _strings),
                          ],
                          const SizedBox(height: AppTheme.spaceSm),
                        ],
                      ),
                    ),
                  ),
                  _buildComposerBar(context, theme, scheme),
                ],
              );

              if (!widget.embedded) composer = SafeArea(child: composer);
              return composer;
            },
          ),
        ),
      ),
    );
  }

  /// The message on one side, who it is from on the other: the screen reads as
  /// a conversation instead of a form with a text field in it.
  List<Widget> _buildMessageBubble(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme scheme,
    required LaunchContext? launch,
    required List<CapturedNotification> captured,
  }) {
    final bubble = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(AppTheme.cardRadius),
          bottomLeft: Radius.circular(AppTheme.cardRadius),
          bottomRight: Radius.circular(AppTheme.cardRadius),
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_context != null) ...[
            Text(
              _context!.displayTitle,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandBright,
              ),
            ),
            const SizedBox(height: 4),
            if (_context!.contextWarnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _context!.contextWarnings.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (captured.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
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
                              : '(no text) ${notification.displayTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _context = value;
                      _messageController.text = value?.displayText ?? '';
                    });
                  },
                ),
              ),
          ] else if (launch != null && launch.hasText)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _strings.fromSource(launch.source.label.toLowerCase()),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          TextField(
            controller: _messageController,
            minLines: 2,
            maxLines: 6,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            // No filled box: the bubble *is* the box, so the message does not
            // sit inside a box inside a box.
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: _strings.messageTextHint,
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            onChanged: (_) => _messageChanged(),
          ),
        ],
      ),
    );

    return [
      if (_context == null && (launch == null || !launch.hasText))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _strings.noMessageCaptured,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: bubble,
        ),
      ),
      if (_context != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(_clearSessionContext),
            icon: const Icon(Icons.close_rounded, size: 14),
            label: Text(_strings.clear),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
        ),
    ];
  }

  Widget _buildQuickReplies(ThemeData theme, List<String> quickReplies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _strings.quickReplies,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppTheme.spaceXs,
          runSpacing: AppTheme.spaceXs,
          children: [
            for (final reply in quickReplies)
              ActionChip(
                label: Text(
                  reply,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => _openLocalReply(reply),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailure(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
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
    );
  }

  /// The drafts, as the other side of the conversation: right-aligned bubbles
  /// with the actions that matter on each one. This replaced a push to a
  /// separate SuggestionsScreen, which hid the drafts on a screen of their own
  /// and added a back tap to every single reply.
  List<Widget> _buildReplyBubbles(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return [
      for (var i = 0; i < _suggestions.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _ReplyBubble(
                key: ValueKey<String>('draft-$i'),
                text: _suggestions[i],
                best: i == 0 && _suggestions.length > 1,
                cached: _cached,
                offline: _offline,
                strings: _strings,
                onCopy: () => _copyDraft(_suggestions[i]),
                onEdit: () => _editDraft(i),
                onShare: () => _shareDraft(_suggestions[i]),
                onSave: () => _saveDraft(_suggestions[i]),
              ),
            ),
          ),
        ),
      if (_generating)
        const Padding(
          padding: EdgeInsets.only(top: AppTheme.spaceSm),
          child: _SuggestionsSkeleton(),
        ),
    ];
  }

  /// Pinned bottom bar: the style in one line, and the action that changes what
  /// is on screen. It never scrolls away.
  Widget _buildComposerBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final style = '${_language.label} · ${_tone.label} · ${_length.label}';
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        AppTheme.spaceSm,
        AppTheme.spaceMd,
        AppTheme.spaceSm + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: AppSurfaces.centered(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _editStyle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        style,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _strings.change,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AppSurfaces.primaryAction(
              context,
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    )
                  : const Icon(AppIcons.generate, size: 19),
              label: _generating
                  ? _strings.generating
                  : _suggestions.isEmpty
                  ? _strings.generateSuggestions
                  : _strings.generateAgain,
            ),
            const SizedBox(height: 6),
            Text(
              _strings.sentOnlyOnGenerate,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
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

/// One draft, as the reply side of the conversation.
///
/// It is a bubble on purpose: the message above is a bubble from them, this is
/// the answer, and the four actions sit under it at a size that reads as
/// "options", not as four equal primary buttons. A copy of this card used to
/// live on a pushed screen; it now sits where the reply is read.
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({
    required this.text,
    required this.best,
    required this.cached,
    required this.offline,
    required this.strings,
    required this.onCopy,
    required this.onEdit,
    required this.onShare,
    required this.onSave,
    super.key,
  });

  final String text;
  final bool best;
  final bool cached;
  final bool offline;
  final AppStrings strings;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: isDark ? 0.22 : 0.09),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppTheme.cardRadius),
          topRight: Radius.circular(AppTheme.cardRadius),
          bottomLeft: Radius.circular(AppTheme.cardRadius),
          bottomRight: Radius.circular(4),
        ),
        border: Border.all(
          color: AppTheme.brand.withValues(alpha: isDark ? 0.34 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (best || cached || offline)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (best)
                    _BubbleTag(
                      label: strings.bestFit,
                      color: AppTheme.brand,
                      isDark: isDark,
                    ),
                  if (cached)
                    _BubbleTag(
                      label: strings.cachedDraft,
                      color: AppTheme.amber,
                      isDark: isDark,
                    ),
                  if (offline)
                    _BubbleTag(
                      label: strings.offlineDraft,
                      color: AppTheme.mint,
                      isDark: isDark,
                    ),
                ],
              ),
            ),
          SelectableText(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _BubbleAction(
                icon: Icons.copy_all_rounded,
                label: strings.copyDraft,
                onTap: onCopy,
              ),
              _BubbleAction(
                icon: Icons.edit_outlined,
                label: strings.editDraft,
                onTap: onEdit,
              ),
              _BubbleAction(
                icon: Icons.share_rounded,
                label: strings.share,
                onTap: onShare,
              ),
              _BubbleAction(
                icon: Icons.bookmark_outline_rounded,
                label: strings.saveAsTemplate,
                onTap: onSave,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A quiet label on a draft: "BEST FIT", "From cache", "On-device suggestion".
class _BubbleTag extends StatelessWidget {
  const _BubbleTag({
    required this.label,
    required this.color,
    required this.isDark,
  });

  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: isDark ? color : Color.lerp(color, Colors.black, 0.25),
        ),
      ),
    );
  }
}

/// One text action under a draft. Not an outlined button: four equal buttons
/// under every draft is what made the old screen read as a form.
class _BubbleAction extends StatelessWidget {
  const _BubbleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The template action keeps its icon and drops its label when there are
  /// four actions on one line; a tooltip and a semantic label keep it usable.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Flexible(
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: scheme.primary),
                  const SizedBox(width: 4),
                  if (!compact)
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
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

/// The composer at rest: one honest line about what to do, instead of a large
/// empty card that looked like something had failed to load.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.theme, required this.strings});

  final ThemeData theme;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 15,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            strings.emptyComposerHint,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
