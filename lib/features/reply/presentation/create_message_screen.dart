import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../settings/providers/preferences_provider.dart';
import '../../memory/data/remembered_facts_store.dart';
import '../../memory/providers/conversation_memory_provider.dart';
import '../data/reply_repository.dart';
import '../data/writer_chat_history_store.dart';
import '../providers/saved_replies_provider.dart';
import '../providers/writer_chat_history_provider.dart';
import 'create_message_history_screen.dart';
import '../domain/reply_refinement.dart';
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

  /// The style this chat is being written in.
  ///
  /// These start from Settings and then belong to the chat, the way a chat app
  /// keeps one voice per conversation. Settings decides what a *reply* sounds
  /// like when it arrives from a notification; it is not a vote on what a
  /// message the user is deliberately composing should sound like. Reading the
  /// tone from Settings on every send meant the chips could not work: whatever
  /// the user picked was overwritten by the stored default one line later.
  ReplyLanguage _language = ReplyLanguage.english;
  ReplyTone _tone = ReplyTone.friendly;
  ReplyLength _length = ReplyLength.short;

  /// Whether the style has been taken from Settings yet. Settings is the
  /// starting point, not the authority - once the user changes a chip (or a
  /// saved chat carries its own style) the screen stops reading it.
  bool _styleSeeded = false;

  /// Where "the chat you were writing" is remembered between launches. A chat
  /// id, not any message text - the text itself lives in the bounded writer
  /// store and is deleted with it.
  static const String _lastChatPrefsKey = 'writer_last_chat_id';

  /// Whether the screen has already tried to reopen the last chat. Only the
  /// first visit restores; arriving from the history list must not be undone by
  /// a background restore a frame later.
  bool _restoredLastChat = false;

  /// Which draft is open for editing, as `turnIndex:replyIndex`. Null means all
  /// drafts are read-only.
  String? _editingDraftKey;

  /// The text being typed into the open draft. Kept out of [_turns] until the
  /// user confirms, so an abandoned edit cannot rewrite the conversation.
  final TextEditingController _draftEditor = TextEditingController();

  /// One message per prompt, deliberately.
  ///
  /// The writer is a conversation, not a suggestion list: two drafts for the
  /// same brief made the screen look like it could not decide, and the user has
  /// to read both before picking. The reply panel still offers several, because
  /// there the choice is the point - here the user already said what they want.
  static const int _suggestionCount = 1;

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    _draftEditor.dispose();
    super.dispose();
  }

  String _draftKey(int turnIndex, int replyIndex) => '$turnIndex:$replyIndex';

  /// Clears the screen for a new conversation.
  ///
  /// The old chat is not deleted - it is already saved, bounded and reachable in
  /// history. This just stops the next message from inheriting its context.
  void _startNewChat() {
    setState(() {
      _turns.clear();
      _historyId = null;
      _editingDraftKey = null;
      _draftEditor.clear();
      _promptController.clear();
      _inputError = null;
    });
  }

  /// Removes one exchange from the conversation.
  ///
  /// Available per turn because "that question was a mistake" is a normal thing
  /// to want to undo, and the only alternative was deleting the whole chat from
  /// the history screen. The turn after it keeps its own text; only the context
  /// it is sent with changes.
  Future<void> _deleteTurn(int turnIndex) async {
    setState(() {
      _turns.removeAt(turnIndex);
      _editingDraftKey = null;
      _draftEditor.clear();
    });
    await _persistHistory();
  }

  /// Opens a draft for editing in place.
  ///
  /// Editing used to mean a trip to another screen and back, which is a strange
  /// thing to ask of a chat: fixing one word in a message the app just wrote is
  /// the most ordinary action there is.
  void _beginEditDraft(int turnIndex, int replyIndex, String text) {
    setState(() {
      _editingDraftKey = _draftKey(turnIndex, replyIndex);
      _draftEditor.text = text;
    });
  }

  void _cancelEditDraft() {
    setState(() {
      _editingDraftKey = null;
      _draftEditor.clear();
    });
  }

  /// Writes the edited text back into the turn.
  ///
  /// The turn keeps the request that produced it: the draft was written in a
  /// particular style and format, and editing its words does not change that.
  /// The cached/offline flags are cleared because the text is no longer what the
  /// provider returned - a "from cache" label on a hand-edited message would be
  /// a lie.
  void _commitEditDraft(int turnIndex, int replyIndex) {
    final text = _draftEditor.text.trim();
    if (text.isEmpty) return;
    setState(() {
      final turn = _turns[turnIndex];
      final replies = List<String>.from(turn.replies);
      replies[replyIndex] = text;
      _turns[turnIndex] = turn.copyWith(
        replies: replies,
        clearCacheFlags: true,
        edited: true,
      );
      _editingDraftKey = null;
      _draftEditor.clear();
    });
    _persistHistory();
  }

  /// The restore pointer is part of what "off" means.
  ///
  /// `ConversationMemorySwitch` deletes the stored conversations when it is
  /// switched off; a leftover id pointing at a chat that no longer exists would
  /// be a dangling record of the user having written something. It is cleared
  /// here, where the chat is being written, and the restore tolerates a stale
  /// id anyway.
  Future<void> _forgetRestorePointer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastChatPrefsKey);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // The chips must show the style the first message will actually use, so the
    // default is taken from Settings before the first frame rather than on the
    // first send.
    _seedStyleFromDefaults();
    _restoreLastChat();
  }

  /// Reopens the chat this device was last writing.
  ///
  /// The screen used to greet a returning user with an empty composer and their
  /// previous work one tap away in history - so every visit started from zero
  /// unless they remembered to go looking. This is not new storage: it reads the
  /// same bounded writer history, and only when the user's memory switch is on.
  Future<void> _restoreLastChat() async {
    if (_restoredLastChat) return;
    _restoredLastChat = true;
    try {
      final memorySwitch = ref.read(conversationMemoryEnabledProvider.notifier);
      await memorySwitch.ready;
      if (!mounted) return;
      if (!ref.read(conversationMemoryEnabledProvider)) {
        // Off means nothing of this is kept - including the pointer.
        await _forgetRestorePointer();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_lastChatPrefsKey);
      if (id == null || !mounted) return;

      final store = ref.read(writerChatHistoryStoreProvider);
      final chats = await store.all();
      final chat = chats.where((item) => item.id == id).firstOrNull;
      if (chat == null || !mounted) return;
      // Nothing on screen yet means the user has not started something new;
      // a restore must never overwrite a brief they are already typing.
      if (_turns.isNotEmpty || _promptController.text.isNotEmpty) return;
      _applySavedChat(chat);
    } catch (_) {
      // A restore that fails is a screen that opens empty - the same screen a
      // first-time user sees. It must never be an error page.
    }
  }

  /// Settings as the starting point for a brand-new chat.
  ///
  /// Called once, so a user who walks in with Professional tone in Settings gets
  /// a professional draft by default - and a user who then taps "Funny" keeps
  /// funny for the rest of the chat.
  void _seedStyleFromDefaults() {
    if (_styleSeeded) return;
    _styleSeeded = true;
    final preferences = ref.read(preferencesProvider);
    _language = preferences.language;
    _tone = preferences.tone;
    _length = preferences.length;
  }

  void _applyStyle({
    ReplyLanguage? language,
    ReplyTone? tone,
    ReplyLength? length,
  }) {
    _seedStyleFromDefaults();
    setState(() {
      _language = language ?? _language;
      _tone = tone ?? _tone;
      _length = length ?? _length;
    });
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

  /// Starting points for a chat message.
  ///
  /// The first four were all addressed to a girlfriend, which told every new
  /// user with a mother, a boss or a friend that this screen was not for them.
  /// Two romantic ideas stay (they are the reason many people install it), and
  /// the rest cover the relationships the earlier list quietly excluded.
  List<({String label, String prompt})> _quickIdeas() {
    final strings = _strings;
    if (_format != WritingFormat.chat) return _documentIdeas();
    final language = strings.language;
    String pick(String en, String bn, String hi) => switch (language) {
      AppLanguage.english => en,
      AppLanguage.bengali => bn,
      AppLanguage.hindi => hi,
    };
    return [
      (
        label: strings.exampleGoodMorning,
        prompt: pick(
          'Write a warm good morning message for my girlfriend.',
          'আমার প্রেমিকাকে পাঠানোর জন্য সুন্দর একটি সুপ্রভাতের মেসেজ লিখে দাও।',
          'मेरी प्रेमिका के लिए एक प्यारा सा सुप्रभात संदेश लिखो।',
        ),
      ),
      (
        label: strings.exampleMissYou,
        prompt: pick(
          'Write a short message telling my girlfriend I miss her.',
          'আমার প্রেমিকাকে মিস করছি—এমন ছোট্ট একটি মিষ্টি মেসেজ লিখে দাও।',
          'मेरी प्रेमिका को याद करने के बारे में एक छोटा, प्यारा संदेश लिखो।',
        ),
      ),
      (
        label: strings.exampleThankSomeone,
        prompt: pick(
          'Write a short, sincere thank-you message for a friend who helped me '
              'move house last weekend.',
          'গত সপ্তাহান্তে বাড়ি বদলাতে সাহায্য করা এক বন্ধুকে ধন্যবাদ জানিয়ে '
              'ছোট্ট একটি আন্তরিক মেসেজ লিখে দাও।',
          'पिछले सप्ताहांत घर बदलने में मदद करने वाले मित्र को धन्यवाद देते हुए '
              'एक छोटा, सच्चा संदेश लिखो।',
        ),
      ),
      (
        label: strings.exampleAskForLeave,
        prompt: pick(
          'Write a polite message to my manager asking for one day off tomorrow '
              'because I have a doctor appointment.',
          'আগামীকাল ডাক্তারের Appointment থাকায় একদিনের ছুটি চেয়ে ম্যানেজারকে '
              'একটি ভদ্র মেসেজ লিখে দাও।',
          'कल डॉक्टर के अपॉइंटमेंट के कारण एक दिन की छुट्टी माँगते हुए मैनेजर को '
              'विनम्र संदेश लिखो।',
        ),
      ),
      (
        label: strings.exampleCheckOnSomeone,
        prompt: pick(
          'Write a caring message to my mother asking how she is feeling after '
              'her fever.',
          'জ্বরের পর মা কেমন আছেন জিজ্ঞেস করে একটি যত্নশীল মেসেজ লিখে দাও।',
          'बुखार के बाद माँ कैसी हैं, यह पूछते हुए एक स्नेही संदेश लिखो।',
        ),
      ),
      (
        label: strings.exampleApologise,
        prompt: pick(
          'Write a sincere apology to a friend I kept waiting for an hour '
              'yesterday.',
          'কাল এক ঘণ্টা অপেক্ষা করিয়ে দেওয়ার জন্য এক বন্ধুর কাছে আন্তরিকভাবে '
              'ক্ষমা চেয়ে একটি মেসেজ লিখে দাও।',
          'कल एक घंटा इंतज़ार कराने के लिए मित्र से सच्चे मन से माफ़ी माँगते हुए '
              'संदेश लिखो।',
        ),
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
    _applySavedChat(saved);
    _scrollToBottom();
  }

  /// Puts a saved chat on screen: its turns, its format and its style.
  ///
  /// Shared by "open from history" and "reopen what I was writing last", because
  /// a restored chat that lost its style - or kept the wrong one - is the same
  /// bug whichever door the user came through.
  void _applySavedChat(WriterChatHistory saved) {
    final restored = <_ChatTurn>[];
    final contextLines = <String>[];
    final fallback = (language: _language, tone: _tone, length: _length);
    ReplyLanguage? restoredLanguage;
    ReplyTone? restoredTone;
    ReplyLength? restoredLength;
    for (final savedTurn in saved.turns) {
      final language = savedTurn.language == null
          ? fallback.language
          : ReplyLanguage.fromCode(savedTurn.language);
      final tone = savedTurn.tone == null
          ? fallback.tone
          : ReplyTone.fromName(savedTurn.tone);
      final length = savedTurn.length == null
          ? fallback.length
          : ReplyLength.fromName(savedTurn.length);
      restoredLanguage ??= language;
      restoredTone ??= tone;
      restoredLength ??= length;
      final request = ReplyRequest(
        message: savedTurn.prompt,
        language: language,
        tone: tone,
        length: length,
        count: _suggestionCount,
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
      if (restoredLanguage != null) _language = restoredLanguage;
      if (restoredTone != null) _tone = restoredTone;
      if (restoredLength != null) _length = restoredLength;
      _styleSeeded = true;
      final firstFormat = saved.turns.first.format;
      if (firstFormat != null) _format = _formatFromId(firstFormat);
      _inputError = null;
      _promptController.clear();
    });
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
            language: turn.request.language.code,
            tone: turn.request.tone.name,
            length: turn.request.length.name,
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
    // Remember *which* chat this was, so the next launch can reopen it. Only an
    // id: the text stays in the bounded writer store, and turning the memory
    // switch off deletes both.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastChatPrefsKey, id);
    } catch (_) {
      // Losing the restore pointer costs a tap through history, nothing more.
    }
    if (mounted) ref.invalidate(writerChatHistoryProvider);
  }

  Future<void> _send({String? prompt}) async {
    if (_generating) return;
    _seedStyleFromDefaults();
    final writingPrompt = (prompt ?? _promptController.text).trim();
    if (writingPrompt.isEmpty) {
      setState(() => _inputError = _strings.createMessageEmpty);
      return;
    }

    // How this user actually writes, when the app has been allowed to keep any
    // of it. Empty list otherwise, and then the prompt's voice block is dropped
    // rather than sent empty.
    final styleExamples = await ref
        .read(conversationMemoryControllerProvider)
        .styleExamplesAcrossChats();
    // Facts the user typed into Settings. Read only when memory is on, because
    // "off" is the switch that means this app keeps nothing about you.
    //
    // Wrapped: an unreadable store loses the facts, not the message. Memory has
    // never been allowed to break generation, and it is not about to start.
    var facts = const <String>[];
    if (ref.read(conversationMemoryEnabledProvider)) {
      try {
        facts = await ref.read(rememberedFactsStoreProvider).promptLines();
      } catch (_) {
        facts = const <String>[];
      }
    }
    if (!mounted) return;

    final request = ReplyRequest(
      message: writingPrompt,
      language: _language,
      tone: _tone,
      length: _length,
      count: _suggestionCount,
      priorMessages: _conversationHistory(),
      styleExamples: styleExamples,
      rememberedFacts: facts,
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

    await _run(turn, _turns.length - 1);
  }

  /// Runs one turn's request and writes the result back into [_turns].
  ///
  /// Shared by the first send, a retry after a failure and a regenerate: they
  /// differ only in whether the cache may be used and whether a turn is added
  /// first. Keeping one implementation is what stops the retry path from
  /// drifting away from the send path - the bug that made a failed turn
  /// unrecoverable was that there was no second path at all.
  Future<void> _run(
    _ChatTurn turn,
    int index, {
    bool bypassCache = false,
  }) async {
    setState(() {
      _generating = true;
      _turns[index] = turn.copyWith(isGenerating: true, clearFailure: true);
    });

    final repository = ref.read(replyRepositoryProvider);
    final result = repository is StreamingReplyRepository
        ? await _runStreaming(repository, turn, index)
        : await repository.generate(turn.request, bypassCache: bypassCache);
    if (!mounted || result == null) return;

    setState(() {
      _generating = false;
      _turns[index] = switch (result) {
        ReplySuccess(:final replies, :final cachedAt, :final offline) =>
          turn.copyWith(
            replies: replies,
            failure: replies.isEmpty ? _strings.refineFailed : null,
            clearFailure: replies.isNotEmpty,
            cachedAt: cachedAt,
            offline: offline,
            isGenerating: false,
          ),
        ReplyFailure(:final message) => turn.copyWith(
          failure: message,
          isGenerating: false,
        ),
      };
    });
    _scrollToBottom();
    await _persistHistory();
  }

  /// Runs a turn as a stream, updating the turn's preview as text arrives.
  ///
  /// Returns the final result, or null when the widget went away mid-stream.
  /// The preview is the *only* thing touched during the run: `replies` stays
  /// empty until a real result lands, so no code path can mistake a half-written
  /// answer for a finished one.
  Future<ReplyResult?> _runStreaming(
    StreamingReplyRepository repository,
    _ChatTurn turn,
    int index,
  ) async {
    ReplyResult? result;
    try {
      await for (final progress in repository.generateStreaming(turn.request)) {
        if (!mounted) return null;
        if (progress.isFinal) {
          result = progress.result;
          break;
        }
        setState(() {
          _turns[index] = _turns[index].copyWith(preview: progress.preview);
        });
      }
    } catch (_) {
      // The repository already maps failures; this is the last resort so a
      // broken stream becomes an honest error instead of a frozen preview.
      result = const ReplyFailure(
        'The connection dropped before the answer was finished.',
        isRetryable: true,
      );
    }
    if (!mounted) return null;
    // Whatever was previewed is dropped here, unconditionally: a stream that
    // ended without a result produced nothing the user may keep.
    setState(() {
      _turns[index] = _turns[index].copyWith(preview: const <String>[]);
    });
    return result ??
        const ReplyFailure(
          'The answer stopped before it was finished. Try again.',
          isRetryable: true,
        );
  }

  /// Rewrites one draft in place, by instruction.
  ///
  /// This is the "change this one sentence" path. The brief stays the same and
  /// the draft is the thing being edited, so it goes through the repository's
  /// refusal path (`draftToRefine` + `refinementInstruction`) rather than being
  /// treated as a brand-new request. One draft out, one draft back: asking for a
  /// variation here would answer a question the user did not ask.
  Future<void> _refineDraft(
    _ChatTurn turn,
    int turnIndex,
    int replyIndex,
    String draft,
    String instruction,
  ) async {
    if (_generating) return;
    setState(() => _generating = true);

    final request = turn.request.copyWith(
      draftToRefine: draft,
      refinementInstruction: instruction,
      count: 1,
    );
    final result = await ref
        .read(replyRepositoryProvider)
        .generate(request, bypassCache: true);
    if (!mounted) return;

    setState(() {
      _generating = false;
      switch (result) {
        case ReplySuccess(:final replies) when replies.isNotEmpty:
          final updated = List<String>.from(_turns[turnIndex].replies);
          updated[replyIndex] = replies.first;
          _turns[turnIndex] = _turns[turnIndex].copyWith(
            replies: updated,
            clearCacheFlags: true,
            edited: true,
          );
        case ReplyFailure(:final message):
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        case ReplySuccess():
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_strings.refineFailed)));
      }
    });
    await _persistHistory();
  }

  /// The instruction box: "make it shorter", "drop the second sentence".
  Future<void> _askForChange(
    _ChatTurn turn,
    int turnIndex,
    int replyIndex,
    String draft,
  ) async {
    final controller = TextEditingController();
    final instruction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceMd,
          right: AppTheme.spaceMd,
          bottom:
              MediaQuery.of(sheetContext).viewInsets.bottom + AppTheme.spaceMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _strings.askChange,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            TextField(
              key: const Key('refineInstructionField'),
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _strings.askChangeHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            // The fixed, well-understood rewrites stay one tap away: they are
            // the common cases, and a free-text box should not be the only door.
            Wrap(
              spacing: AppTheme.spaceXs,
              children: [
                for (final refinement in ReplyRefinement.values)
                  ActionChip(
                    key: ValueKey<String>('refineChip-${refinement.name}'),
                    label: Text(_refinementLabel(refinement)),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(refinement.instruction),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            FilledButton(
              key: const Key('submitRefineInstruction'),
              onPressed: () {
                final text = controller.text.trim();
                Navigator.of(sheetContext).pop(text.isEmpty ? null : text);
              },
              child: Text(_strings.save),
            ),
          ],
        ),
      ),
    );
    // Disposed only after the sheet has finished closing: the field still owns
    // this controller while its route is animating out, and disposing it first
    // threw "a TextEditingController was used after being disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (!mounted || instruction == null) return;
    await _refineDraft(turn, turnIndex, replyIndex, draft, instruction);
  }

  String _refinementLabel(ReplyRefinement refinement) => switch (refinement) {
    ReplyRefinement.shorter => _strings.refineShorter,
    ReplyRefinement.softer => _strings.refineSofter,
    ReplyRefinement.politeDecline => _strings.refineDecline,
    ReplyRefinement.continueConversation => _strings.refineContinue,
  };

  /// Ask for a different draft of the same brief.
  ///
  /// [bypassCache] is the point: the cached answer to this exact request is the
  /// one already on screen, so serving it again would look like the button did
  /// nothing. The request is rebuilt from the turn that is on screen, not from
  /// the current chips, so "another" really is another version of *that*
  /// message and not of a message the user has since re-styled.
  Future<void> _writeAnother(_ChatTurn turn, int index) async {
    if (_generating) return;
    await _run(turn, index, bypassCache: true);
  }

  /// Try the same request again after a failure.
  ///
  /// The same request, not a fresh one: the user changed nothing, so the app
  /// must not quietly drop the style or the format they picked. The message
  /// text is still in the failed turn, so nothing has to be retyped.
  Future<void> _retry(_ChatTurn turn, int index) async {
    if (_generating) return;
    await _run(turn, index);
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

  /// Opens Android's share chooser for a draft.
  ///
  /// Opening the chooser is not sending: the user picks an app and confirms
  /// there. This keeps the invariant in AGENTS.md - the app never sends a
  /// message on the user's behalf, in any layer - while saving the copy/paste
  /// step for people who send from Gmail or a chat app rather than this one.
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
        AppTheme.spaceLg,
        AppTheme.spaceMd,
        AppTheme.spaceLg,
      ),
      children: [
        // The greeting is compact on purpose. The style row and the format row
        // live in the composer, so a tall welcome column pushed the only two
        // controls that shape the answer to the bottom of the screen.
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: theme.colorScheme.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.createMessagePromptLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strings.writeSomethingNewSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceLg),
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

  /// The label a draft needs, or null when it was written in exactly the style
  /// the toolbar promised.
  ///
  /// A repeated `Bengali · Premika · Medium` under every draft was noise - the
  /// pill above the input already said it, and saying it twice made the screen
  /// busier without telling anyone anything. This reports only the surprise.
  String? _draftStyleNote(_ChatTurn turn) {
    final request = turn.request;
    final asked = [_language, _tone, _length];
    final got = [request.language, request.tone, request.length];
    if (request.format != _format) {
      return 'Written as ${_formatLabel(request.format)}';
    }
    for (var i = 0; i < asked.length; i++) {
      if (asked[i] != got[i]) {
        final actual = switch (i) {
          0 => request.language.label,
          1 => request.tone.label,
          _ => request.length.label,
        };
        return 'Written in $actual, not what the style asks for';
      }
    }
    return null;
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Text that has arrived, drawn muted and *under* the
                          // writing indicator. It is a preview, not a draft:
                          // the last event of the stream replaces it with the
                          // real answer or with a failure, and a broken stream
                          // throws it away rather than promoting it.
                          for (final (previewIndex, line)
                              in turn.preview.indexed)
                            Container(
                              key: ValueKey<String>(
                                'streamPreview-$turnIndex-$previewIndex',
                              ),
                              width: double.infinity,
                              margin: const EdgeInsets.only(
                                bottom: AppTheme.spaceSm,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spaceMd,
                                vertical: AppTheme.spaceSm,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(
                                  18,
                                ).copyWith(topLeft: const Radius.circular(6)),
                              ),
                              child: Text(
                                line,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
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
                                turn.preview.isEmpty
                                    ? _strings.generating
                                    : _strings.stillWriting,
                                key: ValueKey<String>(
                                  'streamStatus-$turnIndex',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else if (turn.failure != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            turn.failure!,
                            key: const Key('createMessageFailure'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                          // A failure used to be a dead end: the text was still
                          // here, the style was still chosen, and there was
                          // nothing to press. Retrying costs one provider call
                          // and no retyping.
                          const SizedBox(height: AppTheme.spaceXs),
                          OutlinedButton.icon(
                            key: ValueKey<String>(
                              'retryCreateMessage-$turnIndex',
                            ),
                            onPressed: _generating
                                ? null
                                : () => _retry(turn, turnIndex),
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: Text(_strings.retry),
                          ),
                        ],
                      )
                    else ...[
                      for (final (replyIndex, reply) in turn.replies.indexed)
                        Container(
                          key: ValueKey<String>(
                            'createMessageDraft-$turnIndex-$replyIndex',
                          ),
                          width: double.infinity,
                          margin: const EdgeInsets.only(
                            bottom: AppTheme.spaceSm,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                            // A draft is a message, so it is drawn as one: the
                            // same tail-corner bubble the outgoing prompt uses,
                            // mirrored. A card with a border read like a form.
                            borderRadius: BorderRadius.circular(18)
                                .copyWith(topLeft: const Radius.circular(6)),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_editingDraftKey ==
                                  _draftKey(turnIndex, replyIndex)) ...[
                                // Editing in place: the draft becomes a field
                                // with Save and Cancel. An abandoned edit costs
                                // nothing because nothing was written until
                                // Save.
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.spaceSm,
                                    AppTheme.spaceSm,
                                    AppTheme.spaceSm,
                                    0,
                                  ),
                                  child: TextField(
                                    key: ValueKey<String>(
                                      'editDraftField-$turnIndex-$replyIndex',
                                    ),
                                    controller: _draftEditor,
                                    minLines: 3,
                                    maxLines: 12,
                                    autofocus: true,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.5,
                                    ),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: scheme.surface,
                                      contentPadding: const EdgeInsets.all(
                                        AppTheme.spaceSm,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spaceXs,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        key: ValueKey<String>(
                                          'cancelEditDraft-$turnIndex-$replyIndex',
                                        ),
                                        onPressed: _cancelEditDraft,
                                        child: Text(_strings.cancel),
                                      ),
                                      FilledButton(
                                        key: ValueKey<String>(
                                          'saveEditDraft-$turnIndex-$replyIndex',
                                        ),
                                        onPressed: () => _commitEditDraft(
                                          turnIndex,
                                          replyIndex,
                                        ),
                                        child: Text(_strings.save),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else
                                // A draft is a message, and a message you cannot
                                // fix with one tap is a message you copy out and
                                // fix somewhere else. Tapping the bubble is the
                                // gesture; the pencil says so out loud.
                                InkWell(
                                  key: ValueKey<String>(
                                    'editDraftTap-$turnIndex-$replyIndex',
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _beginEditDraft(
                                    turnIndex,
                                    replyIndex,
                                    reply,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppTheme.spaceMd,
                                      AppTheme.spaceSm + 2,
                                      AppTheme.spaceMd,
                                      AppTheme.spaceSm,
                                    ),
                                    child: Text(
                                      reply,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(height: 1.5),
                                    ),
                                  ),
                                ),
                              // The style is stated once, in the pill. This
                              // line appears only when the draft came back in
                              // something else - because an explicit request
                              // inside the brief ("write it in English") wins
                              // over the chip - which is exactly when a silent
                              // difference would look like a bug.
                              // Where this draft came from. The reply panel has
                              // always said so; the writer counted it and threw
                              // it away, so a cached answer looked exactly like a
                              // fresh one. It sits above the actions because it
                              // qualifies the text, not the buttons.
                              if (turn.offline || turn.cachedAt != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.spaceMd,
                                    0,
                                    AppTheme.spaceMd,
                                    AppTheme.spaceXs,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        turn.offline
                                            ? Icons.offline_bolt_outlined
                                            : Icons.history_toggle_off_rounded,
                                        size: 13,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          turn.offline
                                              ? _strings.offlineDraft
                                              : _strings.fromCacheNote,
                                          key: ValueKey<String>(
                                            'draftSource-$turnIndex-$replyIndex',
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_draftStyleNote(turn) != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.spaceMd,
                                    0,
                                    AppTheme.spaceSm,
                                    AppTheme.spaceXs,
                                  ),
                                  child: Text(
                                    _draftStyleNote(turn)!,
                                    key: ValueKey<String>(
                                      'createMessageDraftStyle-$turnIndex-$replyIndex',
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  // "None of these" needed a way out that is not
                                  // retyping the brief. One draft per prompt
                                  // makes this the common case, not the edge.
                                  TextButton.icon(
                                    key: ValueKey<String>(
                                      'writeAnother-$turnIndex',
                                    ),
                                    onPressed: _generating
                                        ? null
                                        : () => _writeAnother(turn, turnIndex),
                                    icon: _generating
                                        ? SizedBox.square(
                                            dimension: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: scheme.primary,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.refresh_rounded,
                                            size: 16,
                                          ),
                                    label: Text(_strings.writeAnother),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppTheme.spaceSm,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey<String>(
                                      'askChange-$turnIndex-$replyIndex',
                                    ),
                                    tooltip: _strings.askChange,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _generating
                                        ? null
                                        : () => _askForChange(
                                            turn,
                                            turnIndex,
                                            replyIndex,
                                            reply,
                                          ),
                                    icon: const Icon(
                                      Icons.auto_fix_high_rounded,
                                      size: 17,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    key: ValueKey<String>(
                                      'deleteTurn-$turnIndex',
                                    ),
                                    tooltip: _strings.deleteTurn,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _deleteTurn(turnIndex),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey<String>(
                                      'shareCreateMessageDraft-$turnIndex-$replyIndex',
                                    ),
                                    tooltip: _strings.shareDraft,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _shareDraft(reply),
                                    icon: const Icon(
                                      Icons.ios_share_rounded,
                                      size: 17,
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey<String>(
                                      'copyCreateMessageDraft-$turnIndex-$replyIndex',
                                    ),
                                    tooltip: _strings.copyDraft,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _copyDraft(reply),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 17,
                                    ),
                                  ),
                                ],
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

  /// One chip of the style row.
  ///
  /// Selected chips are the ones that will reach the next request, so the row
  /// can be read at a glance instead of being a menu of guesses. The key pattern
  /// (`chatStyle-<axis>-<value>`) is what the widget test taps.
  /// Saved replies, ready to drop into the composer.
  ///
  /// Inserting into the input rather than sending it: a saved reply is a
  /// starting point the user adapts, and the app has never been allowed to send
  /// anything on its own.
  Future<void> _openSavedReplies() async {
    final saved = ref.read(savedRepliesProvider);
    if (saved.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                0,
                AppTheme.spaceMd,
                AppTheme.spaceSm,
              ),
              child: Text(
                _strings.savedReplies,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: saved.length,
                itemBuilder: (context, index) => ListTile(
                  key: ValueKey<String>('savedReply-$index'),
                  title: Text(
                    saved[index],
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(saved[index]),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
          ],
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _promptController.text = chosen;
      _promptController.selection = TextSelection.collapsed(
        offset: _promptController.text.length,
      );
      _inputError = null;
    });
  }

  /// The style chooser: three labelled groups in a bottom sheet.
  ///
  /// A sheet rather than an inline row because the tone axis alone is eight
  /// entries - wider than a phone. Each group keeps its chips on one wrapping
  /// line, so a screen reader and a thumb both find them in the same order.
  Future<void> _openStyleSheet() async {
    final strings = _strings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void pick({
            ReplyLanguage? language,
            ReplyTone? tone,
            ReplyLength? length,
          }) {
            _applyStyle(language: language, tone: tone, length: length);
            setSheetState(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                0,
                AppTheme.spaceMd,
                AppTheme.spaceMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.replyStyle,
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  _styleGroup<ReplyLanguage>(
                    label: strings.languageLabel,
                    id: 'language',
                    current: _language,
                    values: ReplyLanguage.values,
                    labelOf: (language) => language.label,
                    onSelected: (language) => pick(language: language),
                  ),
                  _styleGroup<ReplyTone>(
                    label: strings.toneLabel,
                    id: 'tone',
                    current: _tone,
                    values: ReplyTone.values,
                    labelOf: (tone) => tone.label,
                    onSelected: (tone) => pick(tone: tone),
                  ),
                  _styleGroup<ReplyLength>(
                    label: strings.lengthLabel,
                    id: 'length',
                    current: _length,
                    values: ReplyLength.values,
                    labelOf: (length) => length.label,
                    onSelected: (length) => pick(length: length),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _styleGroup<T>({
    required String label,
    required String id,
    required T current,
    required List<T> values,
    required String Function(T value) labelOf,
    required void Function(T value) onSelected,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Wrap(
            spacing: AppTheme.spaceXs,
            runSpacing: AppTheme.spaceXs,
            children: [
              for (final value in values)
                ChoiceChip(
                  key: ValueKey<String>('chatStyle-$id-${_valueId(value)}'),
                  label: Text(labelOf(value)),
                  selected: value == current,
                  onSelected: (_) => onSelected(value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The stable id for a style value, for keys and logs: the enum name for a
  /// tone or length, the language code for a language.
  String _valueId(Object? value) => switch (value) {
    ReplyLanguage language => language.code,
    ReplyTone tone => tone.name,
    ReplyLength length => length.name,
    _ => value.toString(),
  };

  Widget _buildComposer(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        AppTheme.spaceXs + 2,
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
          // One toolbar, not three rows of chips.
          //
          // The composer used to carry four format chips, nine tone chips and a
          // style pill above the input - about 180 logical pixels of controls
          // for a text box, which on a phone reads as a wall of buttons. The
          // format, the style and the history are all reachable, but each is one
          // small target and the input is the part that gets the room.
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Format: "Letter" alone. Which four exist is a menu, not
                      // a row - a user picks a format once per message.
                      _ComposerPill(
                        key: const Key('openWritingFormatMenu'),
                        icon: _formatIcon(_format),
                        label: _formatCompactLabel(_format),
                        onTap: _generating ? null : _openFormatMenu,
                      ),
                      const SizedBox(width: AppTheme.spaceXs),
                      // Saved replies: text the user wrote earlier and asked to
                      // keep. They lived only in Settings, which meant the one
                      // screen that writes messages could not reuse them.
                      if (ref.watch(savedRepliesProvider).isNotEmpty) ...[
                        _ComposerPill(
                          key: const Key('openSavedReplies'),
                          icon: Icons.bookmarks_outlined,
                          label: _strings.savedReplies,
                          onTap: _generating ? null : _openSavedReplies,
                        ),
                        const SizedBox(width: AppTheme.spaceXs),
                      ],
                      // Style: the whole current style in one pill.
                      _ComposerPill(
                        key: const Key('openChatStyleSheet'),
                        labelKey: const Key('chatStyleSummary'),
                        icon: Icons.tune_rounded,
                        label: _styleSummary,
                        onTap: _generating ? null : _openStyleSheet,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXs + 2),
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
                    // Repaint for the counter as well as the error: a limit the
                    // user only meets by failing a submit is a limit that
                    // ambushes them.
                    setState(() => _inputError = null);
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
          // The counter appears only when it starts to matter - above 80% of the
          // limit - so a short message is not taxed with a number it does not
          // need.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _promptController,
            builder: (context, value, _) {
              final used = value.text.characters.length;
              final limit = AppConstants.maxMessageLength;
              if (used < limit * 0.8) return const SizedBox.shrink();
              final over = used > limit;
              return Padding(
                padding: const EdgeInsets.only(top: AppTheme.spaceXs),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$used / $limit',
                    key: const Key('createMessageCharCount'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: over ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: over ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
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

  /// The label the toolbar has room for. The menu still spells every format
  /// out in full - it is the place a user goes to read the choices.
  String _formatCompactLabel(WritingFormat format) {
    final strings = _strings;
    return switch (format) {
      WritingFormat.chat => strings.formatChat,
      WritingFormat.email => strings.formatEmail,
      WritingFormat.letter => strings.formatLetter,
      WritingFormat.application => strings.formatApplication,
    };
  }

  IconData _formatIcon(WritingFormat format) => switch (format) {
    WritingFormat.chat => Icons.chat_bubble_outline_rounded,
    WritingFormat.email => Icons.mail_outline_rounded,
    WritingFormat.letter => Icons.article_outlined,
    WritingFormat.application => Icons.description_outlined,
  };

  /// `বাংলা · Premika · Medium` - the style the next message will use.
  String get _styleSummary =>
      [_language.label, _tone.label, _length.label].join(' · ');

  Future<void> _openFormatMenu() async {
    final strings = _strings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spaceXs),
              child: Text(
                strings.formatTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final format in WritingFormat.values)
              ListTile(
                key: ValueKey<String>('writingFormat-${format.id}'),
                leading: Icon(_formatIcon(format)),
                title: Text(_formatLabel(format)),
                trailing: format == _format
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  setState(() => _format = format);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('openCreateMessageHistory'),
                        tooltip: _strings.writerHistory,
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history_rounded),
                      ),
                      PopupMenuButton<String>(
                        key: const Key('writerOverflowMenu'),
                        tooltip: _strings.moreActions,
                        onSelected: (value) {
                          if (value == 'new') _startNewChat();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            key: const Key('startNewChatItem'),
                            value: 'new',
                            enabled: _turns.isNotEmpty,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.add_comment_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: AppTheme.spaceSm),
                                Text(_strings.newChat),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
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
    this.edited = false,
    this.preview = const <String>[],
  });

  final String prompt;
  final ReplyRequest request;
  final List<String> replies;
  final String? failure;
  final DateTime? cachedAt;
  final bool offline;
  final bool isGenerating;

  /// True once the user has changed the draft's words by hand. A hand-edited
  /// draft is no longer "from cache" or "offline": it is theirs.
  final bool edited;

  /// Reply strings the provider has already closed, while the rest is still
  /// being written. Shown under a "writing" state and *never* as the answer:
  /// the last event replaces it with [replies] or with a failure, and a stream
  /// that dies leaves this list discarded rather than promoted.
  final List<String> preview;

  _ChatTurn copyWith({
    List<String>? replies,
    String? failure,
    bool clearFailure = false,
    DateTime? cachedAt,
    bool? offline,
    bool? isGenerating,
    bool clearCacheFlags = false,
    bool? edited,
    List<String>? preview,
  }) => _ChatTurn(
    prompt: prompt,
    request: request,
    replies: replies ?? this.replies,
    // `failure: null` cannot mean "no failure" through a ?? fallback, so
    // clearing it is its own flag - otherwise a retried turn kept showing the
    // error it had just recovered from.
    failure: clearFailure ? null : (failure ?? this.failure),
    cachedAt: clearCacheFlags ? null : (cachedAt ?? this.cachedAt),
    offline: clearCacheFlags ? false : (offline ?? this.offline),
    isGenerating: isGenerating ?? this.isGenerating,
    edited: edited ?? this.edited,
    preview: preview ?? this.preview,
  );
}

/// A small labelled pill in the composer toolbar.
///
/// Deliberately quieter than a chip: no border, no fill until pressed. The
/// composer is a place to type, and a toolbar that competes with the text box
/// is the thing this replaced.
class _ComposerPill extends StatelessWidget {
  const _ComposerPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                key: labelKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
