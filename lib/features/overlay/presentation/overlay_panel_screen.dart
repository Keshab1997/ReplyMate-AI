import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/brand_icon.dart';
import '../../../shared/widgets/section_label.dart';
import '../../memory/providers/conversation_memory_provider.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../reply/data/reply_repository.dart';
import '../../reply/domain/reply_request.dart';
import '../../reply/presentation/widgets/suggestion_card.dart';
import '../../settings/providers/preferences_provider.dart';
import '../../settings/settings_screen.dart';
import '../models/overlay_context.dart';
import '../providers/overlay_providers.dart';

/// Screen 10 of docs/SCREEN_SPECIFICATIONS.md: the panel behind the floating
/// reply bubble.
///
/// Design rule for this screen: **the bubble is a shortcut, not a second app.**
/// The reply style (language, tone, length) is whatever the user already chose
/// in Settings - it is *not* re-asked here. The panel therefore has exactly one
/// job: show the message, generate, hand back the reply. Anything that needs a
/// decision opens Settings through the tune icon instead of duplicating the
/// controls (docs/FLOATING_OVERLAY.md §1).
///
/// What it must never do: keep the message after it closes, show message text
/// in a log, offer quick reply without a live RemoteInput action, or claim AI
/// is configured when it is not.
class OverlayPanelScreen extends ConsumerStatefulWidget {
  const OverlayPanelScreen({this.initialContext, super.key});

  /// Injected context, for tests and for the in-app preview of the panel. In
  /// production it is null and the panel consumes the native pending context
  /// instead.
  final OverlayContext? initialContext;

  @override
  ConsumerState<OverlayPanelScreen> createState() => _OverlayPanelScreenState();
}

class _OverlayPanelScreenState extends ConsumerState<OverlayPanelScreen> {
  bool _generating = false;
  ReplyFailure? _failure;
  List<TextEditingController> _controllers = const [];

  /// The message being replied to. Starts as the notification's text and can be
  /// edited or replaced by a pasted one - which is the whole point: when the
  /// app posted no usable text (or the user is looking at a screen ReplyMate
  /// cannot read), pasting the message here still gets a reply.
  final TextEditingController _messageController = TextEditingController();
  bool _initialisedMessage = false;
  bool _editingMessage = false;

  /// The conversation being answered. Normally the one the bubble was opened
  /// for; the switcher can move it to another chat that is also waiting.
  OverlayContext? _active;

  /// The context the current drafts belong to. An accepted reply is filed
  /// against *this* conversation, not whichever one the panel last showed - the
  /// wrong-chat mistake quick reply is already guarded against.
  OverlayContext? _draftingFor;

  @override
  void dispose() {
    _messageController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Closing goes through the platform, never through a Navigator pop: the
  /// panel is the only route in its activity, and a pop used to uncover the
  /// main app behind it.
  Future<void> _close() async {
    final closed = await ref
        .read(notificationsBridgeProvider)
        .closeOverlayPanel();
    if (!mounted) return;
    if (!closed) {
      // In-app preview or a test: there is no activity to finish.
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _generate(OverlayContext overlay) async {
    // Style comes from the user's saved defaults, so the same reply style
    // follows them from the composer into the bubble.
    final preferences = ref.read(preferencesProvider);
    // Conversation memory, when the user switched it on: this both files the
    // message being answered and hands back the window including it
    // (docs/CONVERSATION_MEMORY.md §7). Null means "no memory applies here",
    // and the capture's own history is what the prompt gets instead - exactly
    // what the app did before memory existed.
    final memory = await ref
        .read(conversationMemoryControllerProvider)
        .rememberCapture(overlay.notification);
    if (!mounted) return;
    _draftingFor = overlay;
    final request = ReplyRequest(
      message: _messageController.text,
      language: preferences.language,
      tone: preferences.tone,
      length: preferences.length,
      count: preferences.suggestionCount,
      priorMessages:
          memory?.contextLines() ?? overlay.notification.priorMessages,
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
    switch (result) {
      case ReplySuccess(:final replies):
        for (final controller in _controllers) {
          controller.dispose();
        }
        setState(() {
          _generating = false;
          _controllers = [
            for (final reply in replies) TextEditingController(text: reply),
          ];
        });
      case ReplyFailure(:final message):
        setState(() {
          _generating = false;
          _failure = ReplyFailure(message);
        });
    }
  }

  /// Seeds the editable message once, from whatever the notification exposed.
  /// Assigning during build (no setState) mirrors the composer: the value is
  /// read by this very frame.
  void _initMessage(OverlayContext overlay) {
    if (_initialisedMessage) return;
    _initialisedMessage = true;
    _messageController.text = overlay.displayText;
  }

  /// One card is not "Suggestions", and a lone card must not be badged
  /// "BEST FIT" as though it had beaten the others.
  String get _suggestionsLabel =>
      _strings.suggestionsLabel(_controllers.length);

  /// Moves the panel to another waiting chat. The message box is reset to that
  /// chat's text and the old reply drafts are dropped: replies written for one
  /// conversation must never be offered for another (that is the wrong-chat
  /// mistake quick reply is already guarded against).
  void _switchTo(OverlayContext overlay) {
    if (_active?.notification.key == overlay.notification.key) return;
    setState(() {
      _active = overlay;
      _initialisedMessage = false;
      _editingMessage = false;
      _failure = null;
      for (final controller in _controllers) {
        controller.dispose();
      }
      _controllers = const [];
    });
  }

  AppStrings get _strings => ref.read(appStringsProvider);

  Future<void> _copyMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_strings.messageCopied)));
  }

  /// Pulls text off the clipboard into the message box. This is the supported
  /// route for the one case the listener cannot cover - a conversation the
  /// messaging app never posted a notification for.
  Future<void> _pasteMessage() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (pasted.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_strings.clipboardEmpty)));
      return;
    }
    setState(() {
      _messageController.text = pasted;
      _editingMessage = true;
      _failure = null;
    });
  }

  /// A reply the user copies or shares is a reply they accepted, and the only
  /// reliable source of the user's own voice (docs/CONVERSATION_MEMORY.md §8).
  /// Fire and forget: memory must never make sending a reply wait.
  void _rememberAccepted(String text) {
    final target = _draftingFor;
    if (target == null) return;
    unawaited(
      ref
          .read(conversationMemoryControllerProvider)
          .rememberAcceptedReply(capture: target.notification, text: text),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _rememberAccepted(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_strings.replyCopied)));
  }

  Future<void> _share(String text) async {
    final opened = await ref.read(notificationsBridgeProvider).shareText(text);
    if (opened) _rememberAccepted(text);
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
    final consumed = ref.watch(overlayContextProvider);
    final overlay = widget.initialContext ?? consumed.value;
    final loading = widget.initialContext == null && consumed.isLoading;
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;

    return Scaffold(
      // The activity is translucent. The card, rather than the scaffold,
      // supplies contrast so the conversation remains faintly visible.
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.48),
                      Colors.black.withValues(alpha: 0.64),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(AppTheme.spaceMd),
            child: AnimatedPadding(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - value)),
                      child: Transform.scale(
                        scale: 0.975 + (0.025 * value),
                        child: child,
                      ),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 460,
                      maxHeight: 760,
                    ),
                    child: _GlassCard(child: _buildBody(overlay, loading)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(OverlayContext? overlay, bool loading) {
    if (loading) {
      return _buildPanelShell(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppTheme.spaceXl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (overlay == null) {
      return _buildPanelShell(child: _buildNothing());
    }
    return _buildPanelShell(overlay: overlay, child: _buildPanel(overlay));
  }

  Widget _buildPanelShell({OverlayContext? overlay, required Widget child}) {
    return Semantics(
      key: const Key('overlayPanelSemantics'),
      container: true,
      explicitChildNodes: true,
      label: 'ReplyMate floating reply panel',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(overlay),
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: 0.55),
          ),
          Flexible(
            child: overlay == null
                ? SingleChildScrollView(child: child)
                : child,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(OverlayContext? overlay) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _active ?? overlay;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: 0.24),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: active == null
                ? const BrandIcon(
                    type: BrandIconType.reply,
                    color: Colors.white,
                    size: 22,
                  )
                : Center(
                    child: Text(
                      active.displayTitle.characters.first.toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active?.displayTitle ?? 'ReplyMate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 1),
                Text(
                  active == null
                      ? 'Your reply copilot'
                      : 'via ${active.appLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _strings.settings,
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded, size: 21),
          ),
          IconButton(
            tooltip: _strings.close,
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, size: 22),
          ),
        ],
      ),
    );
  }

  /// The honest dead end: the pending message was consumed by another launch
  /// or lost with the process. Saying so beats an empty panel that looks
  /// broken (docs/FLOATING_OVERLAY.md §11).
  Widget _buildNothing() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mark_chat_unread_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  _strings.nothingToReplyTo,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(_strings.messageGoneBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(_strings.close),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSwitcher(OverlayContext overlay) {
    final others =
        ref.watch(pendingOverlayContextsProvider).value ??
        const <OverlayContext>[];
    // The open chat first, then the rest in arrival order, deduplicated by key
    // (the open one is usually also in the pending list).
    final seen = <String>{overlay.notification.key};
    final chats = <OverlayContext>[
      overlay,
      for (final other in others)
        if (seen.add(other.notification.key)) other,
    ];
    if (chats.length < 2) return const <Widget>[];
    final theme = Theme.of(context);
    return [
      const SizedBox(height: AppTheme.spaceSm),
      SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chats.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppTheme.spaceSm),
          itemBuilder: (context, index) {
            final chat = chats[index];
            final selected = chat.notification.key == overlay.notification.key;
            return AppSurfaces.pill(
              context,
              accent: selected,
              onTap: () => _switchTo(chat),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.circle : Icons.circle_outlined,
                    size: 7,
                    color: selected
                        ? AppTheme.brandBright
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    chat.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildMessageBlock(OverlayContext overlay) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = _messageController.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(AppTheme.tileRadius),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.58),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.34,
            ),
            child: _editingMessage
                ? TextField(
                    controller: _messageController,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: _strings.pasteHint,
                    ),
                    onChanged: (_) => setState(() => _failure = null),
                  )
                : SingleChildScrollView(
                    child: Text(
                      empty
                          ? _strings.noTextInNotification
                          : _messageController.text,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: empty ? null : _copyMessage,
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Copy'),
            ),
            TextButton.icon(
              onPressed: _pasteMessage,
              icon: const Icon(Icons.content_paste_rounded, size: 17),
              label: Text(_strings.paste),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _editingMessage = !_editingMessage),
              icon: Icon(
                _editingMessage ? Icons.check_rounded : Icons.edit_outlined,
                size: 16,
              ),
              label: Text(_editingMessage ? 'Done' : 'Edit'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPanel(OverlayContext initial) {
    final overlay = _active ?? initial;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preferences = ref.watch(preferencesProvider);
    _initMessage(overlay);
    final firebaseReady = ref.watch(firebaseReadyProvider);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        0,
        AppTheme.spaceMd,
        AppTheme.spaceMd,
      ),
      children: [
        ..._buildSwitcher(overlay),
        const SizedBox(height: AppTheme.spaceMd),
        _buildMessageBlock(overlay),
        // Only real limitations appear here. A single-chat WhatsApp
        // notification is not "grouped", and text that arrived is not
        // "redacted" - those lines used to appear anyway and taught the user
        // to ignore the honest ones.
        if (overlay.contextWarnings.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spaceSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTheme.spaceXs),
              Expanded(
                child: Text(
                  overlay.contextWarnings.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppTheme.spaceMd),
        // The style lives in Settings, not here: one place to change it, one
        // place to explain it. Tapping the row opens Settings.
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: _openSettings,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSm,
              vertical: AppTheme.spaceSm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Text(
                    '${preferences.language.label} · '
                    '${preferences.tone.label} · '
                    '${preferences.length.label}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  _strings.change,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: AppTheme.spaceXs),
                Icon(Icons.chevron_right, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
        if (!firebaseReady) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            _strings.aiNotConfiguredPanel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_failure != null) ...[
          const SizedBox(height: AppTheme.spaceMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius - 8),
            ),
            child: Text(
              _failure!.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spaceMd),
        FilledButton.icon(
          onPressed: _generating ? null : () => _generate(overlay),
          icon: _generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const BrandIcon(
                  type: BrandIconType.reply,
                  color: Colors.white,
                  size: 20,
                ),
          label: Text(
            _generating
                ? _strings.generating
                : (preferences.suggestionCount == 1
                      ? _strings.generateAReply
                      : _strings.generateSuggestionsCount(
                          preferences.suggestionCount,
                        )),
          ),
        ),
        if (_controllers.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spaceMd),
          SectionLabel(_suggestionsLabel),
          for (var index = 0; index < _controllers.length; index++) ...[
            SuggestionCard(
              controller: _controllers[index],
              onCopy: _copy,
              onShare: _share,
              best: index == 0 && _controllers.length > 1,
              strings: _strings,
            ),
            const SizedBox(height: AppTheme.spaceSm),
          ],
        ],
      ],
    );
  }
}

/// A floating surface with a real backdrop blur and enough tint to keep text
/// readable over a busy chat. High-contrast users get an effectively solid
/// card instead of glass; reduced-motion users skip only the entrance motion.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final solid = media.highContrast;
    final radius = BorderRadius.circular(24);
    final surface = dark ? AppTheme.inkSurface : Colors.white;

    return Container(
      key: const Key('overlayGlassCard'),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.38 : 0.22),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          key: Key(solid ? 'overlaySolidBackdrop' : 'overlayBlurredBackdrop'),
          filter: ImageFilter.blur(
            sigmaX: solid ? 0 : 20,
            sigmaY: solid ? 0 : 20,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: solid
                    ? scheme.outline
                    : (dark
                          ? Colors.white.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.82)),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface.withValues(alpha: solid ? 1 : (dark ? 0.94 : 0.95)),
                  surface.withValues(alpha: solid ? 1 : (dark ? 0.90 : 0.92)),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
