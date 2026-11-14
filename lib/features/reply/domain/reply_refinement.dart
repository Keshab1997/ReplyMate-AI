/// User-initiated rewrite actions. These are sent only after a user taps one.
enum ReplyRefinement {
  shorter('Make this reply shorter without dropping its main point.'),
  softer('Make this reply warmer and less blunt without changing its meaning.'),
  politeDecline(
    'Rewrite this as a polite decline. Do not invent a reason or extra facts.',
  ),
  continueConversation(
    'Continue the conversation by appending at most one concise, relevant '
    'question to the draft. Use only the incoming message and earlier context. '
    'Preserve the user’s stated position. Never invent facts, plans, promises, '
    'availability or reasons. If no follow-up question is clearly useful, '
    'return the original draft unchanged.',
  );

  const ReplyRefinement(this.instruction);

  final String instruction;
}
