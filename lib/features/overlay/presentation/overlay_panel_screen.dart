import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
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

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
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
      message: overlay.displayText,
      language: preferences.language,
      tone: preferences.tone,
      length: preferences.length,
      count: AppConstants.maxSuggestionCount,
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

  /// Quick reply only ever targets the notification this panel was opened for,
  /// and only when that notification carried a live RemoteInput action. A
  /// stale key is refused by the native layer, and the refusal is explained -
  /// never swallowed and never retried against a different chat.
  Future<void> _quickReply(OverlayContext overlay, String text) async {
    if (!overlay.notification.hasReplyAction) {
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
        .sendQuickReply(text, notificationKey: overlay.notification.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Reply handed to ${overlay.appLabel}.'
              : 'The reply action is no longer valid. '
                    'Copy the reply and paste it in the app instead.',
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
              onTap: () => Navigator.of(context).maybePop(),
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
                onPressed: () => Navigator.of(context).maybePop(),
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
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(OverlayContext overlay) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preferences = ref.watch(preferencesProvider);
    final quickReplyAvailable = overlay.notification.hasReplyAction;
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
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
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        // The message itself: quoted, read-only, capped so a long message
        // scrolls inside the panel instead of pushing the button off screen.
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
            child: SingleChildScrollView(
              child: Text(
                overlay.displayText.isEmpty
                    ? 'This notification exposed no message text. There is '
                          'nothing to reply to here.'
                    : overlay.displayText,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ),
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
          label: Text(_generating ? 'Generating…' : 'Generate suggestions'),
        ),
        if (_controllers.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spaceMd),
          const SectionLabel('Suggestions'),
          for (final controller in _controllers) ...[
            SuggestionCard(
              controller: controller,
              quickReplyAvailable: quickReplyAvailable,
              onCopy: _copy,
              onShare: _share,
              onQuickReply: (text) => _quickReply(overlay, text),
            ),
            const SizedBox(height: AppTheme.spaceSm),
          ],
          if (!quickReplyAvailable)
            Text(
              'This notification has no reply action, so quick reply is not '
              'offered. Copy the reply and paste it in the app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
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
