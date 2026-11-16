/// What a standalone writing request should produce.
///
/// The chat screen used to write one thing: a chat message. That is the wrong
/// shape for half of what people actually ask it for - a leave application, a
/// letter to a landlord, an email to a professor - and the difference is not
/// tone or length: a letter has a date line and a salutation, an email has a
/// subject, an application has a recipient block. A model told only "polite,
/// short" writes a chat message with the word "Dear" in front of it.
///
/// So the format is part of the request, not a hint inside the prompt text:
/// it reaches the system prompt, the token budget and the cache key.
enum WritingFormat {
  /// The original behaviour: a message someone could send in a chat.
  chat,

  /// A complete email: subject line, greeting, body, sign-off.
  email,

  /// A letter: date, salutation, body, closing.
  letter,

  /// A formal application (leave, job, permission): recipient block, subject,
  /// salutation, purpose, request, closing.
  application;

  /// True for the formats that need room. A one-line reply and a four-paragraph
  /// application cannot share a 300-token ceiling.
  bool get isDocument => this != WritingFormat.chat;

  /// The format rules appended to the system prompt.
  ///
  /// Kept here rather than in the prompt builder so every entry point that
  /// knows a format - chat screen, saved history, a future share-sheet action -
  /// gets the same instructions without copying text.
  String get promptRules => switch (this) {
    WritingFormat.chat => '',
    WritingFormat.email =>
      '- The user is writing an email. Start with a line beginning "Subject:", '
          'then a greeting to the recipient by role or name, then one to three '
          'short paragraphs, then a sign-off and a placeholder signature such '
          'as [Your name]. No Markdown, no bullet points.\n',
    WritingFormat.letter =>
      '- The user is writing a letter. Start with a date line, then a '
          'salutation, then two to four short paragraphs, then a closing line '
          'and a placeholder signature such as [Your name]. No Markdown.\n',
    WritingFormat.application =>
      '- The user is writing a formal application. Start with a recipient block '
          '(for example "To," then "The Principal," then the institution), then '
          'a "Subject:" line, then a salutation, then three or four short '
          'paragraphs covering the purpose, the relevant facts the user gave, '
          'the request, and a closing courtesy, then a signature placeholder '
          'such as [Your name]. Formal register, no Markdown, no invented '
          'details: where a fact is missing (dates, roll number, address) '
          'leave a bracketed placeholder instead of making one up.\n',
  };

  /// The shortest honest label, for logs and tests. The UI uses the localized
  /// label from `AppStrings`.
  String get id => name;
}
