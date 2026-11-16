import '../../../core/constants/reply_options.dart';

/// Rule-based reply candidates that cost nothing at all.
///
/// Not a model, and it must never be dressed as one. This is the layer that
/// keeps the app useful when there is no key, no Firebase, or no network —
/// the moments when a reply assistant that cannot write a reply is simply
/// broken.
///
/// It reads the incoming message with plain heuristics and returns a small,
/// honest set of candidates. Where the message says nothing it can answer, it
/// returns nothing rather than inventing a reply: an empty list is the truthful
/// answer to "I don't know what to say to this".
class OfflineSuggestions {
  OfflineSuggestions._();

  /// The kind of message this is, as far as a regex can tell.
  static OfflineIntent intentOf(String message) {
    final text = message.toLowerCase().trim();
    if (text.isEmpty) return OfflineIntent.unknown;

    if (_question.hasMatch(text)) return OfflineIntent.question;
    if (_thanks.hasMatch(text)) return OfflineIntent.thanks;
    if (_apology.hasMatch(text)) return OfflineIntent.apology;
    if (_greeting.hasMatch(text)) return OfflineIntent.greeting;
    if (_farewell.hasMatch(text)) return OfflineIntent.farewell;
    if (_ack.hasMatch(text)) return OfflineIntent.acknowledgement;
    if (_plan.hasMatch(text)) return OfflineIntent.plan;
    return OfflineIntent.unknown;
  }

  /// Candidates for [message] in [language] and [tone].
  ///
  /// Never more than [count], never empty-but-pretending: an empty list means
  /// "this layer has nothing useful to say", and the caller should say the same
  /// thing rather than show a placeholder as a suggestion.
  /// [exclude] is the "different one, please" case: lines the user is already
  /// looking at are filtered out, so asking again from the rules layer returns
  /// something they have not seen. When the table is exhausted the result is
  /// empty, which is the signal to spend a real provider call.
  static List<String> forMessage(
    String message, {
    required ReplyLanguage language,
    required ReplyTone tone,
    required ReplyLength length,
    int count = 1,
    Set<String> exclude = const <String>{},
  }) {
    final intent = intentOf(message);
    final table = _tables[language] ?? _tables[ReplyLanguage.english]!;
    final candidates = <String>[
      // The tone's own line leads when there is one, so choosing "funny" and
      // asking for one suggestion actually gets a funny one. The plain answer
      // still follows it, never replaced: the tone is an option, not a filter.
      ...?table[_toneKey(tone)],
      ...?table[intent],
    ]..removeWhere((line) => exclude.contains(line.trim()));
    if (candidates.isEmpty) return const [];
    // Length is expressed by the table's own wording, not by padding text:
    // a short tone gets a short line because that is what is written.
    return candidates.take(count).toList();
  }

  /// A starter line for a message that has not been written yet.
  ///
  /// Different job from [forMessage]: there is no incoming message to classify,
  /// so the intent is unknown by definition and only the greeting/thanks/
  /// apology-style openers make sense. These are openers, not whole messages -
  /// the user finishes them. Labelled offline wherever they are shown, exactly
  /// like the reply path, because an on-device line must never pass for a model's
  /// writing.
  static List<String> forBrief(
    String brief, {
    required ReplyLanguage language,
    required ReplyTone tone,
    required ReplyLength length,
    int count = 1,
  }) {
    final text = brief.toLowerCase();
    // The brief can still hint at the kind of message: "thank my friend" is a
    // thanks, even though nothing arrived.
    final hinted = _thanks.hasMatch(text)
        ? OfflineIntent.thanks
        : _apology.hasMatch(text)
        ? OfflineIntent.apology
        : _greeting.hasMatch(text)
        ? OfflineIntent.greeting
        : OfflineIntent.unknown;
    final table = _tables[language] ?? _tables[ReplyLanguage.english]!;
    final candidates = <String>[
      ...?table[hinted],
      ...?table[_toneKey(tone)],
      ...?table[OfflineIntent.greeting],
    ];
    if (candidates.isEmpty) return const [];
    return candidates.take(count).toList(growable: false);
  }

  static OfflineIntent _toneKey(ReplyTone tone) => switch (tone) {
    ReplyTone.polite => OfflineIntent.polite,
    ReplyTone.funny => OfflineIntent.funny,
    ReplyTone.professional => OfflineIntent.professional,
    _ => OfflineIntent.unknown,
  };

  // Detection. Each pattern is deliberately narrow: a false "question" match
  // produces a confident wrong reply, which is worse than no suggestion.
  static final RegExp _question = RegExp(
    r'\?|؟|क्या|কি\b|কী\b|kya|ki\b|what|when|where|who|why|how|kothay|kobe|keno',
  );
  static final RegExp _thanks = RegExp(
    r'thank|thanks|thx|ধন্যবাদ|শুকরিয়া|धन्यवाद|शुक्रिया|shukriya|dhonnobad',
  );
  static final RegExp _apology = RegExp(
    r'sorry|sry|দুঃখিত|মাফ|ক্ষমা|माफ|क्षमा|maaf|khyoma',
  );

  /// Word boundaries are ASCII-only in Dart, so the non-Latin greetings are
  /// matched without `\b` — with it, "नमस्ते" never matched and a greeting fell
  /// through to "unknown".
  static final RegExp _greeting = RegExp(
    r'(\b(hi|hello|hey|hii|salam|assalam)\b)|নমস্কার|হ্যালো|হাই|नमस्ते|हैलो',
  );
  static final RegExp _farewell = RegExp(
    r'\b(bye|good ?night|see you|পরে কথা|বিদায়|अलविदा|फिर मिलेंगे)\b',
  );
  static final RegExp _ack = RegExp(
    r'^(ok|okay|k|hmm|hmmm|thik|ঠিক|হুম|हाँ|हां|अच्छा|accha|achha)\b',
  );
  static final RegExp _plan = RegExp(
    r'\b(meet|meeting|plan|কখন|কোথায়|সময়|मिल|कब|कहाँ|kobe|kothay|plan)\b',
  );

  /// The tables. Kept as data so adding a language is an entry, not a branch,
  /// and so a test can assert every language has the same keys.
  static const Map<ReplyLanguage, Map<OfflineIntent, List<String>>> _tables = {
    ReplyLanguage.bengali: {
      OfflineIntent.question: [
        'একটু দেখে জানাচ্ছি।',
        'তুমি একটু বিস্তারিত বলবে?',
      ],
      OfflineIntent.thanks: ['আর কিছু লাগলে বলো।', 'স্বাগতম!'],
      OfflineIntent.apology: ['ঠিক আছে, চিন্তা কোরো না।'],
      OfflineIntent.greeting: ['হ্যালো! কেমন আছো?', 'হ্যাঁ বলো।'],
      OfflineIntent.farewell: ['পরে কথা হবে, ভালো থেকো।'],
      OfflineIntent.acknowledgement: ['ঠিক আছে।', 'হুম, বুঝেছি।'],
      OfflineIntent.plan: ['আমি দেখে জানাচ্ছি।'],
      OfflineIntent.polite: ['দয়া করে একটু অপেক্ষা করুন, জানাচ্ছি।'],
      OfflineIntent.professional: ['জানানোর জন্য ধন্যবাদ, দেখে জানাচ্ছি।'],
      OfflineIntent.funny: ['আমি রাজি, তবে চা আগে!'],
      OfflineIntent.unknown: [],
    },
    ReplyLanguage.hindi: {
      OfflineIntent.question: [
        'थोड़ा देखकर बताता हूँ।',
        'थोड़ा और बता सकते हो?',
      ],
      OfflineIntent.thanks: ['कोई बात नहीं।', 'कुछ और चाहिए तो बताइए।'],
      OfflineIntent.apology: ['ठीक है, चिंता मत करो।'],
      OfflineIntent.greeting: ['नमस्ते! कैसे हो?', 'हाँ, बोलो।'],
      OfflineIntent.farewell: ['फिर मिलेंगे, ध्यान रखना।'],
      OfflineIntent.acknowledgement: ['ठीक है।', 'हम्म, समझ गया।'],
      OfflineIntent.plan: ['देखकर बताता हूँ।'],
      OfflineIntent.polite: ['कृपया थोड़ा इंतज़ार करें, बता देता हूँ।'],
      OfflineIntent.professional: ['बताने के लिए धन्यवाद, देखकर बताता हूँ।'],
      OfflineIntent.funny: ['मैं तैयार हूँ, पहले चाय!'],
      OfflineIntent.unknown: [],
    },
    ReplyLanguage.english: {
      OfflineIntent.question: [
        'Let me check and get back to you.',
        'Could you tell me a little more?',
      ],
      OfflineIntent.thanks: ['Anytime.', 'Glad it helped.'],
      OfflineIntent.apology: ['No worries at all.'],
      OfflineIntent.greeting: ['Hey! How are you?', 'Hi — go ahead.'],
      OfflineIntent.farewell: ['Talk soon, take care.'],
      OfflineIntent.acknowledgement: ['Got it.', 'Okay, noted.'],
      OfflineIntent.plan: ['Let me check and confirm.'],
      OfflineIntent.polite: [
        'Please give me a moment — I will confirm shortly.',
      ],
      OfflineIntent.professional: [
        'Thanks for the update — I will check and revert.',
      ],
      OfflineIntent.funny: ['I am in, but only after chai.'],
      OfflineIntent.unknown: [],
    },
  };
}

enum OfflineIntent {
  question,
  thanks,
  apology,
  greeting,
  farewell,
  acknowledgement,
  plan,
  // tone keys live in the same table; they are not intents the message "is"
  polite,
  professional,
  funny,
  unknown,
}
