import '../../../core/constants/reply_options.dart';
import '../domain/reply_request.dart';

/// Builds the two prompts for a generation request.
/// The system prompt carries the prompt rules from
/// verbatim in spirit: preserve meaning, invent nothing, respect language /
/// tone / length, and return machine-readable output the app can validate -
/// because a reply the app cannot parse must never be shown as a success.
class ReplyPrompt {
  ReplyPrompt._();

  static String system(
    int count,
    ReplyTone tone, {
    List<String> styleExamples = const <String>[],
  }) =>
      '''
You are ReplyMate AI, a reply-drafting assistant for everyday conversations.

Rules:
- Preserve the intended meaning of the incoming message.
- Do not invent facts about the user or the sender.
${_relationshipRule(tone)}${_persona(tone)}${_voice(styleExamples)}- Keep replies natural and concise.
- Respect the requested language, tone and length exactly.
- Do not generate harmful or deceptive content.
- Never mention that you are an AI unless the message asks for it.

Return ONLY a JSON object of this exact shape, with exactly $count replies:
{"replies": ["...", "..."]}
''';

  /// The one rule the partner voices have to answer for.
  /// "Do not assume a relationship" is a rule with teeth: a reply that assumes
  /// an intimacy the user never asked for is the kind of thing that makes a
  /// messaging app embarrassing to hand to someone. These two tones are the
  /// exception, and they are an exception only because the user chose them -
  /// picking "Premika" *is* saying who to write as.
  static String _relationshipRule(ReplyTone tone) {
    if (tone.isRomantic) {
      return '- The user chose the ${tone.label} voice, so write as that '
          'partner would. Invent no shared history, no names, no plans: the '
          'closeness is in how it is said, never in facts you make up.\n';
    }
    return '- Do not assume a relationship between the participants.\n';
  }

  /// Shows the model how this user actually writes.
  /// Examples beat adjectives: "casual" gets a model to write *a* casual reply,
  /// while two lines the user really sent get it to write *their* casual reply.
  /// The block is fenced and labelled so the model copies the register and not
  /// the words - and it says outright that these are not messages to answer,
  /// because a model handed stray lines will otherwise reply to them.
  static String _voice(List<String> styleExamples) {
    if (styleExamples.isEmpty) return '';
    final lines = styleExamples.map((line) => '- $line').join('\n');
    return '''
How this user writes, in their own words (examples only - do not reply to
these, do not repeat their content, match the way they say things):
$lines
''';
  }

  /// What a partner voice needs said out loud.
  /// A label alone does not tell a model to use তুমি instead of আপনি, or to
  /// keep the emojis to two. Left unsaid it writes the Bengali equivalent of a
  /// greetings card, which is worse than useless - it reads as copy-pasted.
  static String _persona(ReplyTone tone) {
    if (!tone.isRomantic) return '';
    final partner = tone == ReplyTone.premika
        ? 'a girlfriend writing to the man she loves'
        : 'a boyfriend writing to the woman he loves';
    return '''
Voice for this reply: you are $partner.
- Address them as তুমি in Bengali, never আপনি; as तुम in Hindi, never आप. That
  one pronoun is the difference between a partner and a stranger.
- Warm, a little teasing, genuinely fond. Write it the way it would be said out
  loud to someone, not the way it would be printed on a card.
- One or two love emojis at the most (🥰 💕 😘). Never a row of them, and never
  on every line.
- No pet names you were not given, no memories or plans you were not told.
''';
  }

  /// A request that asks for "their voice" carries style examples; one that
  /// does not carries an empty list, and then the whole voice block — the
  /// largest block of input tokens in the prompt — is dropped rather than sent
  /// empty.
  static String user(ReplyRequest request) =>
      '''${_conversation(request)}Incoming message:
${request.trimmedMessage}

Write ${request.count} reply suggestion(s).
Language: ${request.language.label}
Tone: ${request.tone.label}
Length: ${request.length.label}
''';

  /// What led up to the message, when the capture carried it. Without this the
  /// model answers one line with no idea what it is answering - and "shall we
  /// move it to Friday?" is unanswerable on its own.
  static String _conversation(ReplyRequest request) {
    if (request.priorMessages.isEmpty) return '';
    final lines = request.priorMessages.map((line) => '- $line').join('\n');
    return 'Earlier in this conversation:\n$lines\n\n';
  }
}
