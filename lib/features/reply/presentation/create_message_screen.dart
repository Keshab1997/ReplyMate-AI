import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../settings/providers/preferences_provider.dart';
import '../../memory/providers/conversation_memory_provider.dart';
import '../data/reply_repository.dart';
import '../data/writer_chat_history_store.dart';
import '../providers/writer_chat_history_provider.dart';
import 'create_message_history_screen.dart';
import '../domain/reply_request.dart';
import '../domain/writing_format.dart';
import 'suggestions_screen.dart';

/// A private, ephemeral AI chat for creating messages from a writing brief.
/// Replies remain drafts; the user reviews and chooses what to do with them.
class CreateMessageScreen extends ConsumerStatefulWidget {
  const CreateMessageScreen({super.key});

  @override
  ConsumerState<CreateMessageScreen> createState() =>
      _CreateMessageScreenState();
}

class _CreateMessageScreenState extends ConsumerState<CreateMessageScreen> {
  AppStrings get _strings => ref.read(appStringsProvider);

  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatTurn> _turns = <_ChatTurn>[];
  bool _generating = false;
  String? _inputError;
  String? _historyId;

  /// What the next draft should be. Chat by default (the screen's original
  /// job); email, letter and application change the prompt contract, not just
  /// the wording, because a letter has a date line and an application has a
  /// recipient block.
  WritingFormat _format = WritingFormat.chat;

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatLabel(WritingFormat format) {
    final strings = _strings;
    return switch (format) {
      WritingFormat.chat => strings.formatChat,
      WritingFormat.email => strings.formatEmail,
      WritingFormat.letter => strings.formatLetter,
      WritingFormat.application => strings.formatApplication,
    };
  }

  /// Ideas that show the chosen format rather than a chat message. A quick idea
  /// is also the only tutorial most people read, so it should look like the
  /// thing they are about to get.
  List<({String label, String prompt})> _documentIdeas() {
    final strings = _strings;
    return switch (_format) {
      WritingFormat.email => [
        (
          label: switch (strings.language) {
            AppLanguage.english => 'Email to a teacher',
            AppLanguage.bengali => 'শিক্ষককে ইমেইল',
            AppLanguage.hindi => 'शिक्षक को ईमेल',
          },
          prompt: switch (strings.language) {
            AppLanguage.english =>
              'Write an email to my teacher asking for two extra days to submit '
                  'my assignment because I was unwell.',
            AppLanguage.bengali =>
              'আমার শিক্ষককে ইমেইল লিখে দাও—অসুস্থ থাকায় অ্যাসাইনমেন্ট জমা দিতে '
                  'আরও দুই দিন সময় চেয়ে।',
            AppLanguage.hindi =>
              'मेरे शिक्षक को ईमेल लिखो — बीमार होने के कारण असाइनमेंट जमा करने के '
                  'लिए दो दिन और समय माँगते हुए।',
          },
        ),
        (
          label: switch (strings.language) {
            AppLanguage.english => 'Email to a landlord',
            AppLanguage.bengali => 'বাড়িওয়ালাকে ইমেইল',
            AppLanguage.hindi => 'मकान मालिक को ईमेल',
          },
          prompt: switch (strings.language) {
            AppLanguage.english =>
              'Write a polite email to my landlord asking him to repair the '
                  'leaking tap in the bathroom.',
            AppLanguage.bengali =>
              'বাথরুমের কলের লিক মেরামতের অনুরোধ জানিয়ে বাড়িওয়ালাকে ভদ্রভাবে '
                  'একটি ইমেইল লিখে দাও।',
            AppLanguage.hindi =>
              'बाथरूम के नल की मरम्मत के लिए मकान मालिक को विनम्र ईमेल लिखो।',
          },
        ),
      ],
      WritingFormat.letter => [
        (
          label: switch (strings.language) {
            AppLanguage.english => 'Letter to a friend',
            AppLanguage.bengali => 'বন্ধুকে চিঠি',
            AppLanguage.hindi => 'मित्र को पत्र',
          },
          prompt: switch (strings.language) {
            AppLanguage.english =>
              'Write a warm letter to my old friend telling him I miss our '
                  'college days.',
            AppLanguage.bengali =>
              'পুরোনো বন্ধুকে একটি আন্তরিক চিঠি লিখে দাও—কলেজের দিনগুলো মিস করছি '
                  'বলে।',
            AppLanguage.hindi => 'पुराने मित्र को भावपूर्ण पत्र लिखो कि मैं कॉलेज के दिन याद करता हूँ।',
          },
        ),
        (
          label: switch (strings.language) {
            AppLanguage.english => 'Thank-you letter',
            AppLanguage.bengali => 'ধন্যবাদপত্র',
            AppLanguage.hindi => 'धन्यवाद पत्र',
          },
          prompt: switch (strings.language) {
            AppLanguage.english => 'Write a letter thanking my uncle for helping me during my exams.',
            AppLanguage.bengali =>
              'পরীক্ষার সময় সাহায্য করার জন্য মামাকে ধন্যবাদ জানিয়ে একটি চিঠি '
                  'লিখে দাও।',
            AppLanguage.hindi =>
              'परीक्षा के दौरान मदद के लिए मामा जी को धन्यवाद पत्र लिखो।',
          },
        ),
      ],
      WritingFormat.application => [
        (
          label: switch (strings.language) {
            AppLanguage.english => 'Leave application',
            AppLanguage.bengali => 'ছুটির আবেদন',
            AppLanguage.hindi => 'अवकाश आवेदन',
          },
          prompt: switch (strings.language) {
            AppLanguage.english =>
              'Write a leave application to my principal for three days because '
                  'of fever. I am in class 10, roll 23.',
            AppLanguage.bengali =>
              'জ্বরে তিন দিনের ছুটি চেয়ে অধ্যক্ষ বরাবর একটি আবেদনপত্র লিখে দাও। '
                  'আমি দশম শ্রেণির, রোল ২৩।',
            AppLanguage.hindi =>
              'बुखार के कारण तीन दिन के अवकाश के लिए प्रधानाचार्य को आवेदन लिखो। '
                  'मैं दसवीं कक्षा में हूँ, रोल 23।',
          },
        ),
        (
          label: switch (strings.language) {
            AppLanguage.english => 'Job application',
            AppLanguage.bengali => 'চাকরির আবেদন',
            AppLanguage.hindi => 'नौकरी आवेदन',
          },
          prompt: switch (strings.language) {
            AppLanguage.english =>
              'Write a job application for a junior Flutter developer role. I '
                  'have two years of experience and have shipped three apps.',
            AppLanguage.bengali =>
              'জুনিয়র ফ্লাটার ডেভেলপার পদে চাকরির আবেদন লিখে দাও। আমার দুই বছরের '
                  'অভিজ্ঞতা এবং তিনটি অ্যাপ প্রকাশ করা আছে।',
            AppLanguage.hindi =>
              'जूनियर फ्लटर डेवलपर पद के लिए नौकरी आवेदन लिखो। मेरे दो साल का '
                  'अनुभव है और तीन ऐप प्रकाशित हैं।',
          },
        ),
      ],
      WritingFormat.chat => const [],
    };
  }

  List<({String label, String prompt})> _quickIdeas() {
    final strings = _strings;
    if (_format != WritingFormat.chat) return _documentIdeas();
    return [
      (
        label: strings.exampleRomanticQuote,
        prompt: switch (strings.language) {
          AppLanguage.english =>
            'Write a short, sweet romantic quote for my girlfriend.',
          AppLanguage.bengali =>
            'আমার প্রেমিকার জন্য ছোট্ট, মিষ্টি একটি রোমান্টিক উক্তি লিখে দাও।',
          AppLanguage.hindi =>
            'मेरी प्रेमिका के लिए एक छोटा, प्यारा रोमांटिक कथन लिखो।',
        },
      ),
      (
        label: strings.exampleGoodMorning,
        prompt: switch (strings.language) {
          AppLanguage.english =>
            'Write a warm good morning message for my girlfriend.',
          AppLanguage.bengali => 'আমার প্রেমিকাকে পাঠানোর জন্য সুন্দর একটি সুপ্রভাতের মেসেজ লিখে দাও।',
          AppLanguage.hindi =>
            'मेरी प्रेमिका के लिए एक प्यारा सा सुप्रभात संदेश लिखो।',
        },
      ),
      (
        label: strings.exampleMissYou,
        prompt: switch (strings.language) {
          AppLanguage.english =>
            'Write a short message telling my girlfriend I miss her.',
          AppLanguage.bengali =>
            'আমার প্রেমিকাকে মিস করছি—এমন ছোট্ট একটি মিষ্টি মেসেজ লিখে দাও।',
          AppLanguage.hindi =>
            'मेरी प्रेमिका को याद करने के बारे में एक छोटा, प्यारा संदेश लिखो।',
        },
      ),
      (
        label: strings.exampleMakeHerSmile,
        prompt: switch (strings.language) {
          AppLanguage.english =>
            'Write a light, affectionate message to make my girlfriend smile.',
          AppLanguage.bengali => 'আমার প্রেমিকার মুখে হাসি ফোটানোর জন্য হালকা, আদুরে একটা কথা লিখে দাও।',
          AppLanguage.hindi => 'मेरी प्रेमिका के चेहरे पर मुस्कान लाने के लिए एक हल्का-फुल्का, प्यारा संदेश लिखो।',
        },
      ),
    ];
  }

  /// A saved turn's format, defaulting to chat for turns written before formats
  /// existed.
  WritingFormat _formatFromId(String? id) {
    for (final format in WritingFormat.values) {
      if (format.id == id) return format;
    }
    return WritingFormat.chat;
  }

  List<String> _conversationHistory() {
    final history = <String>[];
    for (final turn in _turns) {
      history.add('User: ${turn.prompt}');
      for (final reply in turn.replies) {
        history.add('Assistant: $reply');
      }
    }
    // Keep recent turns useful without letting a long chat grow every prompt.
    return history.length <= 12
        ? history
        : history.sublist(history.length - 12);
  }

  Future<void> _openHistory() async {
    final saved = await Navigator.of(context).push<WriterChatHistory>(
      MaterialPageRoute<WriterChatHistory>(
        builder: (_) => const CreateMessageHistoryScreen(),
      ),
    );
    if (!mounted || saved == null) return;
    final preferences = ref.read(preferencesProvider);
    final restored = <_ChatTurn>[];
    final contextLines = <String>[];
    for (final savedTurn in saved.turns) {
      final request = ReplyRequest(
        message: savedTurn.prompt,
        language: preferences.language,
        tone: preferences.tone,
        length: preferences.length,
        count: preferences.suggestionCount,
        priorMessages: List<String>.unmodifiable(contextLines),
        mode: ReplyMode.createMessage,
        format: _formatFromId(savedTurn.format),
      );
      restored.add(
        _ChatTurn(
          prompt: savedTurn.prompt,
          request: request,
          replies: savedTurn.replies,
          isGenerating: false,
        ),
      );
      contextLines.add('User: ${savedTurn.prompt}');
      for (final reply in savedTurn.replies) {
        contextLines.add('Assistant: $reply');
      }
    }
    setState(() {
      _historyId = saved.id;
      _turns
        ..clear()
        ..addAll(restored);
      _inputError = null;
      _promptController.clear();
    });
    _scrollToBottom();
  }

  Future<void> _persistHistory() async {
    final memorySwitch = ref.read(conversationMemoryEnabledProvider.notifier);
    await memorySwitch.ready;
    if (!mounted || !ref.read(conversationMemoryEnabledProvider)) return;
    final savedTurns = _turns
        .where((turn) => !turn.isGenerating)
        .map(
          (turn) => WriterChatTurn(
            prompt: turn.prompt,
            replies: turn.replies,
            format: turn.request.format.id,
          ),
        )
        .toList(growable: false);
    if (savedTurns.isEmpty) return;
    final id = _historyId ?? DateTime.now().microsecondsSinceEpoch.toString();
    _historyId = id;
    await ref
        .read(writerChatHistoryStoreProvider)
        .save(
          WriterChatHistory(
            id: id,
            updatedAt: DateTime.now(),
            turns: savedTurns,
          ),
        );
    if (mounted) ref.invalidate(writerChatHistoryProvider);
  }

  Future<void> _send({String? prompt}) async {
    if (_generating) return;
    final writingPrompt = (prompt ?? _promptController.text).trim();
    if (writingPrompt.isEmpty) {
      setState(() => _inputError = _strings.createMessageEmpty);
      return;
    }

    final preferences = ref.read(preferencesProvider);
    final request = ReplyRequest(
      message: writingPrompt,
      language: preferences.language,
      tone: preferences.tone,
      length: preferences.length,
      count: preferences.suggestionCount,
      priorMessages: _conversationHistory(),
      mode: ReplyMode.createMessage,
      format: _format,
    );
    final problems = request.validate();
    if (problems.isNotEmpty) {
      setState(() => _inputError = problems.join(' '));
      return;
    }

    final turn = _ChatTurn(prompt: writingPrompt, request: request);
    setState(() {
      _generating = true;
      _inputError = null;
      _promptController.clear();
      _turns.add(turn);
    });
    _scrollToBottom();

    final result = await ref.read(replyRepositoryProvider).generate(request);
    if (!mounted) return;

    setState(() {
      _generating = false;
      switch (result) {
        case ReplySuccess(:final replies, :final cachedAt, :final offline):
          _turns[_turns.length - 1] = turn.copyWith(
            replies: replies,
            failure: replies.isEmpty ? _strings.refineFailed : null,
            cachedAt: cachedAt,
            offline: offline,
            isGenerating: false,
          );
        case ReplyFailure(:final message):
          _turns[_turns.length - 1] = turn.copyWith(
            failure: message,
            isGenerating: false,
          );
      }
    });
    _scrollToBottom();
    await _persistHistory();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _copyDraft(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_strings.replyCopied)));
  }

  Future<void> _reviewDrafts(_ChatTurn turn) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SuggestionsScreen(
          replies: turn.replies,
          request: turn.request,
          cachedAt: turn.cachedAt,
          offline: turn.offline,
        ),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    final strings = _strings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        AppTheme.spaceXl,
        AppTheme.spaceMd,
        AppTheme.spaceLg,
      ),
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Text(
          strings.createMessagePromptLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Text(
          strings.writeSomethingNewSubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXl),
        Text(
          strings.createMessageExamples,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Wrap(
          spacing: AppTheme.spaceXs,
          runSpacing: AppTheme.spaceXs,
          children: [
            for (final (index, idea) in _quickIdeas().indexed)
              ActionChip(
                key: ValueKey<String>('create-message-idea-$index'),
                label: Text(idea.label),
                onPressed: _generating
                    ? null
                    : () => _send(prompt: idea.prompt),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTurn(BuildContext context, _ChatTurn turn, int turnIndex) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceMd,
        vertical: AppTheme.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20)
                      .copyWith(bottomRight: const Radius.circular(6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceMd,
                    vertical: AppTheme.spaceSm,
                  ),
                  child: Text(
                    turn.prompt,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (turn.isGenerating)
                      Row(
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spaceSm),
                          Text(
                            _strings.generating,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    else if (turn.failure != null)
                      Text(
                        turn.failure!,
                        key: const Key('createMessageFailure'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      )
                    else ...[
                      for (final (replyIndex, reply) in turn.replies.indexed)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(
                            bottom: AppTheme.spaceSm,
                          ),
                          padding: const EdgeInsets.all(AppTheme.spaceMd),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppTheme.cardRadius,
                            ),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                reply,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  key: ValueKey<String>(
                                    'copyCreateMessageDraft-$turnIndex-$replyIndex',
                                  ),
                                  tooltip: _strings.copyDraft,
                                  onPressed: () => _copyDraft(reply),
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (turn.replies.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const Key('reviewCreateMessageDrafts'),
                            onPressed: () => _reviewDrafts(turn),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(_strings.editDraft),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        AppTheme.spaceSm,
        AppTheme.spaceMd,
        AppTheme.spaceSm,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Four formats, always visible: this is the difference between "a
          // message" and "an application", and hiding it behind a menu made the
          // screen look like it could only write one of them.
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppTheme.spaceXs,
                runSpacing: AppTheme.spaceXs,
                children: [
                  for (final format in WritingFormat.values)
                    ChoiceChip(
                      key: ValueKey<String>('writingFormat-${format.id}'),
                      label: Text(_formatLabel(format)),
                      selected: _format == format,
                      onSelected: _generating
                          ? null
                          : (_) => setState(() => _format = format),
                    ),
                ],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('createMessagePromptField'),
                  controller: _promptController,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) {
                    if (_inputError != null) {
                      setState(() => _inputError = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: _strings.createMessagePromptHint,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.65,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceMd,
                      vertical: AppTheme.spaceSm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: scheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              IconButton.filled(
                key: const Key('createMessageSendButton'),
                tooltip: _strings.generateSuggestions,
                onPressed: _generating ? null : () => _send(),
                icon: _generating
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
          if (_inputError != null) ...[
            const SizedBox(height: AppTheme.spaceXs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _inputError!,
                key: const Key('createMessageInputError'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AppSurfaces.centered(
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spaceMd,
                  AppTheme.spaceSm,
                  AppTheme.spaceMd,
                  0,
                ),
                child: ScreenHeader(
                  title: _strings.createMessageTitle,
                  showBack: true,
                  trailing: IconButton(
                    key: const Key('openCreateMessageHistory'),
                    tooltip: _strings.writerHistory,
                    onPressed: _openHistory,
                    icon: const Icon(Icons.history_rounded),
                  ),
                ),
              ),
              Expanded(
                child: _turns.isEmpty
                    ? _buildWelcome(context)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTheme.spaceMd,
                        ),
                        itemCount: _turns.length,
                        itemBuilder: (context, index) =>
                            _buildTurn(context, _turns[index], index),
                      ),
              ),
              _buildComposer(context),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatTurn {
  const _ChatTurn({
    required this.prompt,
    required this.request,
    this.replies = const <String>[],
    this.failure,
    this.cachedAt,
    this.offline = false,
    this.isGenerating = true,
  });

  final String prompt;
  final ReplyRequest request;
  final List<String> replies;
  final String? failure;
  final DateTime? cachedAt;
  final bool offline;
  final bool isGenerating;

  _ChatTurn copyWith({
    List<String>? replies,
    String? failure,
    DateTime? cachedAt,
    bool? offline,
    bool? isGenerating,
  }) => _ChatTurn(
    prompt: prompt,
    request: request,
    replies: replies ?? this.replies,
    failure: failure ?? this.failure,
    cachedAt: cachedAt ?? this.cachedAt,
    offline: offline ?? this.offline,
    isGenerating: isGenerating ?? this.isGenerating,
  );
}
