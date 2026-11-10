import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/mascot_face.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/widgets/section_label.dart';
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
    final request = ReplyRequest(
      message: _messageController.text,
      language: preferences.language,
      tone: preferences.tone,
      length: preferences.length,
      count: preferences.suggestionCount,
      priorMessages: overlay.notification.priorMessages,
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
      _controllers.length == 1 ? 'Suggestion' : 'Suggestions';

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

  Future<void> _copyMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied. Paste it anywhere.')),
    );
  }

  /// Pulls text off the clipboard into the message box. This is the supported
  /// route for the one case the listener cannot cover - a conversation the
  /// messaging app never posted a notification for.
  Future<void> _pasteMessage() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (pasted.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('The clipboard is empty.')));
      return;
    }
    setState(() {
      _messageController.text = pasted;
      _editingMessage = true;
      _failure = null;
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Reply copied.')));
  }

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
    final consumed = ref.watch(overlayContextProvider);
    final overlay = widget.initialContext ?? consumed.value;
    final loading = widget.initialContext == null && consumed.isLoading;

    return Scaffold(
      // Translucent: the messaging app stays visible behind the panel, so the
      // user never loses the conversation they are answering.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping outside the panel dismisses it, like any sheet.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _close(),
              child: const SizedBox.expand(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceSm),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppTheme.cardRadius),
                        bottom: Radius.circular(AppTheme.cardRadius),
                      ),
                    ),
                    child: _buildBody(overlay, loading),
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
      return const Padding(
        padding: EdgeInsets.all(AppTheme.spaceLg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (overlay == null) {
      return _buildNothing();
    }
    return _buildPanel(overlay);
  }

  /// The honest dead end: the pending message was consumed by another launch
  /// or lost with the process. Saying so beats an empty panel that looks
  /// broken (docs/FLOATING_OVERLAY.md §11).
  Widget _buildNothing() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Grabber(),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nothing to reply to',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune),
                onPressed: _openSettings,
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => _close(),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'This message is no longer available. ReplyMate keeps a message '
            'only in memory, so it is gone once the panel closes or the app is '
            'stopped. Wait for the next message, or paste the text in the '
            'composer.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTheme.spaceMd),
          OutlinedButton(onPressed: () => _close(), child: const Text('Close')),
        ],
      ),
    );
  }

  /// The message: quoted and copyable by default, editable and pasteable on
  /// demand. Generation always uses what is in this box, so a pasted message
  /// and a captured one take the same path - which is what makes the panel
  /// useful even when the notification carried nothing.
  /// A row of chat chips, shown only when more than one conversation is
  /// waiting. WhatsApp can ping you three times while ReplyMate is on screen;
  /// before this, the badge said 3 but the panel could only ever answer the
  /// last one.
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
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius - 6),
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
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'Paste the message you want to reply to',
                    ),
                    onChanged: (_) => setState(() => _failure = null),
                  )
                : SingleChildScrollView(
                    child: Text(
                      empty
                          ? 'This notification exposed no message text. Use '
                                'Paste below to reply to something yourself.'
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
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Copy'),
            ),
            TextButton.icon(
              onPressed: _pasteMessage,
              icon: const Icon(Icons.content_paste_go, size: 16),
              label: const Text('Paste'),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _editingMessage = !_editingMessage),
              icon: Icon(
                _editingMessage ? Icons.check : Icons.edit_outlined,
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
        const _Grabber(),
        Row(
          children: [
            // The same face as the bubble the user just tapped: thinking while
            // the request is in flight, happy once there are replies.
            MascotFace(
              size: 34,
              glow: false,
              animate: false,
              mood: _generating
                  ? MascotMood.thinking
                  : (_controllers.isNotEmpty
                        ? MascotMood.happy
                        : MascotMood.idle),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overlay.displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'via ${overlay.appLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: _openSettings,
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => _close(),
            ),
          ],
        ),
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
                  'Change',
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
            'AI generation is not configured on this install, so generating '
            'will explain that instead of inventing a reply.',
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
              : const Icon(Icons.auto_awesome),
          label: Text(
            _generating
                ? 'Generating…'
                : (preferences.suggestionCount == 1
                      ? 'Generate a reply'
                      : 'Generate ${preferences.suggestionCount} suggestions'),
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
            ),
            const SizedBox(height: AppTheme.spaceSm),
          ],
        ],
      ],
    );
  }
}

/// The little bar that says "this is a sheet you can flick away".
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppTheme.spaceSm,
          bottom: AppTheme.spaceSm,
        ),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
