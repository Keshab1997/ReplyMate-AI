/// User-initiated rewrite actions. These are sent only after a user taps one.
enum ReplyRefinement {
  shorter('Make this reply shorter without dropping its main point.'),
  softer('Make this reply warmer and less blunt without changing its meaning.'),
  politeDecline(
    'Rewrite this as a polite decline. Do not invent a reason or extra facts.',
  );

  const ReplyRefinement(this.instruction);

  final String instruction;
}
