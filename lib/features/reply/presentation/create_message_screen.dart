import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../settings/providers/preferences_provider.dart';
import '../data/reply_repository.dart';
import '../domain/reply_request.dart';
import 'suggestions_screen.dart';

/// A separate writing path for creating a new message from a free-form brief.
/// It deliberately does not require an incoming chat message.
class CreateMessageScreen extends ConsumerStatefulWidget {
  const CreateMessageScreen({super.key});

  @override
  ConsumerState<CreateMessageScreen> createState() =>
      _CreateMessageScreenState();
}

class _CreateMessageScreenState extends ConsumerState<CreateMessageScreen> {
  AppStrings get _strings => ref.read(appStringsProvider);

  final TextEditingController _promptController = TextEditingController();
  bool _generating = false;
  String? _failure;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  List<({String label, String prompt})> _quickIdeas() {
    final strings = _strings;
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

  Future<void> _generate({String? prompt}) async {
    if (_generating) return;
    if (prompt != null) _promptController.text = prompt;
    final writingPrompt = _promptController.text.trim();
    if (writingPrompt.isEmpty) {
      setState(() => _failure = _strings.createMessageEmpty);
      return;
    }

    final preferences = ref.read(preferencesProvider);
    final request = ReplyRequest(
      message: writingPrompt,
      language: preferences.language,
      tone: preferences.tone,
      length: preferences.length,
      count: preferences.suggestionCount,
      mode: ReplyMode.createMessage,
    );
    final problems = request.validate();
    if (problems.isNotEmpty) {
      setState(() => _failure = problems.join(' '));
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
      case ReplySuccess(:final replies, :final cachedAt, :final offline):
        if (replies.isEmpty) {
          setState(() => _failure = _strings.refineFailed);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuggestionsScreen(
              replies: replies,
              request: request,
              cachedAt: cachedAt,
              offline: offline,
            ),
          ),
        );
      case ReplyFailure(:final message):
        setState(() => _failure = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strings = _strings;

    return Scaffold(
      body: SafeArea(
        child: AppSurfaces.centered(
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  children: [
                    ScreenHeader(
                      title: strings.createMessageTitle,
                      showBack: true,
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Text(
                      strings.writeSomethingNewSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    Text(
                      strings.createMessagePromptLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    TextField(
                      key: const Key('createMessagePromptField'),
                      controller: _promptController,
                      minLines: 4,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: strings.createMessagePromptHint,
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.cardRadius,
                          ),
                        ),
                      ),
                      onChanged: (_) {
                        if (_failure != null) {
                          setState(() => _failure = null);
                        }
                      },
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    Text(
                      strings.createMessageExamples,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceXs),
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
                                : () => _generate(prompt: idea.prompt),
                          ),
                      ],
                    ),
                    if (_failure != null) ...[
                      const SizedBox(height: AppTheme.spaceMd),
                      Text(
                        _failure!,
                        key: const Key('createMessageFailure'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: AppSurfaces.primaryAction(
                  context,
                  onPressed: _generating ? null : () => _generate(),
                  icon: _generating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 19),
                  label: _generating
                      ? strings.generating
                      : strings.generateSuggestions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
