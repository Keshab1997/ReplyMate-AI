import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/widgets/choice_chips.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../reply/data/reply_repository.dart';
import '../../reply/domain/reply_request.dart';
import '../../reply/presentation/widgets/suggestion_card.dart';
import '../models/overlay_context.dart';
import '../providers/overlay_providers.dart';

/// Screen 10 of docs/SCREEN_SPECIFICATIONS.md: the panel behind the floating
/// reply bubble.
///
/// Reached only from the bubble - never from normal navigation - so it is built
/// as a translucent sheet over whatever the user was doing, not as a page. It
/// reuses the composer's chips and the suggestions screen's cards on purpose:
/// one reply flow, two entry points (docs/FLOATING_OVERLAY.md §4.2).
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
  ReplyLanguage _language = ReplyLanguage.english;
  ReplyTone _tone = ReplyTone.friendly;
  ReplyLength _length = ReplyLength.short;

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

  Future<void> _generate(OverlayContext context) async {
    final request = ReplyRequest(
      message: context.displayText,
      language: _language,
      tone: _tone,
      length: _length,
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
                    maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
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
          Row(
            children: [
              Text(
                'Nothing to reply to',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
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
    final quickReplyAvailable = overlay.notification.hasReplyAction;
    final firebaseReady = ref.watch(firebaseReadyProvider);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overlay.appLabel,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    overlay.displayTitle,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceSm),
        // The message itself: read-only, capped so a long message scrolls
        // inside the panel instead of pushing the controls off screen.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: SingleChildScrollView(
            child: Text(
              overlay.displayText.isEmpty
                  ? 'This notification exposed no message text. There is '
                        'nothing to reply to here.'
                  : overlay.displayText,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        if (overlay.contextWarnings.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            overlay.contextWarnings.join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppTheme.spaceMd),
        ChoiceChips<ReplyLanguage>(
          options: ReplyLanguage.values,
          selected: _language,
          labelOf: (language) => language.label,
          onSelected: (language) => setState(() => _language = language),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        ChoiceChips<ReplyTone>(
          options: ReplyTone.values,
          selected: _tone,
          labelOf: (tone) => tone.label,
          onSelected: (tone) => setState(() => _tone = tone),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        ChoiceChips<ReplyLength>(
          options: ReplyLength.values,
          selected: _length,
          labelOf: (length) => length.label,
          onSelected: (length) => setState(() => _length = length),
        ),
        if (!firebaseReady) ...[
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'AI generation is not configured on this install, so generating '
            'will explain that instead of inventing a reply.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_failure != null) ...[
          const SizedBox(height: AppTheme.spaceMd),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              child: Text(
                _failure!.message,
                style: Theme.of(context).textTheme.bodyMedium,
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
        for (final controller in _controllers) ...[
          const SizedBox(height: AppTheme.spaceMd),
          SuggestionCard(
            controller: controller,
            quickReplyAvailable: quickReplyAvailable,
            onCopy: _copy,
            onShare: _share,
            onQuickReply: (text) => _quickReply(overlay, text),
          ),
        ],
        if (_controllers.isNotEmpty && !quickReplyAvailable) ...[
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'This notification has no reply action, so quick reply is not '
            'offered. Copy the reply and paste it in the app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
