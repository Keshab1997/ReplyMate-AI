import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../../shared/widgets/choice_chips.dart';
import '../../../shared/widgets/section_label.dart';
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
  const ReplyComposerScreen({super.key});

  @override
  ConsumerState<ReplyComposerScreen> createState() =>
      _ReplyComposerScreenState();
}

class _ReplyComposerScreenState extends ConsumerState<ReplyComposerScreen> {
  final TextEditingController _messageController = TextEditingController();

  ReplyLanguage _language = ReplyLanguage.english;
  ReplyTone _tone = ReplyTone.friendly;
  ReplyLength _length = ReplyLength.short;
  int _count = AppConstants.maxSuggestionCount;

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
    } else if (captured.isNotEmpty) {
      _context = captured.first;
      _messageController.text = captured.first.displayText;
    }
  }

  Future<void> _generate() async {
    final request = ReplyRequest(
      message: _messageController.text,
      language: _language,
      tone: _tone,
      length: _length,
      count: _count,
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

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _clearSessionContext();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('New reply')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            children: [
              const SectionLabel('Message context'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_context != null) ...[
                        Text(
                          _context!.displayTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        if (_context!.contextWarnings.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTheme.spaceSm,
                            ),
                            child: Text(
                              _context!.contextWarnings.join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (captured.length > 1)
                          DropdownButton<CapturedNotification>(
                            isExpanded: true,
                            value: _context,
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
                      ] else
                        Text(
                          launch != null && launch.hasText
                              ? 'From ${launch.source.label.toLowerCase()}.'
                              : 'Paste or type the message you received.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: AppTheme.spaceSm),
                      TextField(
                        controller: _messageController,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Message text…',
                        ),
                        onChanged: (_) => setState(() => _failure = null),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              const SectionLabel('Output language'),
              ChoiceChips<ReplyLanguage>(
                options: ReplyLanguage.values,
                selected: _language,
                labelOf: (language) => language.label,
                onSelected: (language) => setState(() => _language = language),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              const SectionLabel('Tone'),
              ChoiceChips<ReplyTone>(
                options: ReplyTone.values,
                selected: _tone,
                labelOf: (tone) => tone.label,
                onSelected: (tone) => setState(() => _tone = tone),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              const SectionLabel('Length'),
              ChoiceChips<ReplyLength>(
                options: ReplyLength.values,
                selected: _length,
                labelOf: (length) => length.label,
                onSelected: (length) => setState(() => _length = length),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              const SectionLabel('Number of suggestions'),
              ChoiceChips<int>(
                options: List<int>.generate(
                  AppConstants.maxSuggestionCount -
                      AppConstants.minSuggestionCount +
                      1,
                  (index) => AppConstants.minSuggestionCount + index,
                ),
                selected: _count,
                labelOf: (count) => '$count',
                onSelected: (count) => setState(() => _count = count),
              ),
              if (_failure != null) ...[
                const SizedBox(height: AppTheme.spaceLg),
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
              const SizedBox(height: AppTheme.spaceLg),
              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _generating ? 'Generating…' : 'Generate suggestions',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
