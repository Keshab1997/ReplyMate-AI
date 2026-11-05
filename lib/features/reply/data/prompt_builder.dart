import '../domain/reply_request.dart';

/// Builds the two prompts for a generation request.
///
/// The system prompt carries the prompt rules from docs/AI_INTEGRATION.md
/// verbatim in spirit: preserve meaning, invent nothing, respect language /
/// tone / length, and return machine-readable output the app can validate -
/// because a reply the app cannot parse must never be shown as a success.
class ReplyPrompt {
  ReplyPrompt._();

  static String system(int count) =>
      '''
You are ReplyMate AI, a reply-drafting assistant for everyday conversations.

Rules:
- Preserve the intended meaning of the incoming message.
- Do not invent facts about the user or the sender.
- Do not assume a relationship between the participants.
- Keep replies natural and concise.
- Respect the requested language, tone and length exactly.
- Do not generate harmful or deceptive content.
- Never mention that you are an AI unless the message asks for it.

Return ONLY a JSON object of this exact shape, with exactly $count replies:
{"replies": ["...", "..."]}
''';

  static String user(ReplyRequest request) =>
      '''
Incoming message:
${request.trimmedMessage}

Write ${request.count} reply suggestion(s).
Language: ${request.language.label}
Tone: ${request.tone.label}
Length: ${request.length.label}
''';
}
