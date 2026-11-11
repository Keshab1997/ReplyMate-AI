/// The three axes every reply request carries (FR-06, FR-07 and the length
/// control from docs/AI_INTEGRATION.md). Keeping them as enums makes an
/// invalid combination unrepresentable and gives the validation tests
/// something concrete to bite on.
enum ReplyLanguage {
  bengali('bn', 'Bengali'),
  hindi('hi', 'Hindi'),
  english('en', 'English');

  const ReplyLanguage(this.code, this.label);

  final String code;
  final String label;

  static ReplyLanguage fromCode(String? code) => values.firstWhere(
    (language) => language.code == code,
    orElse: () => ReplyLanguage.english,
  );
}

/// All six tones from PRODUCT_REQUIREMENTS.md FR-06, plus the two partner
/// voices. The README's marketing list shows five; the requirement document is
/// the source of truth for the first six.
///
/// [ReplyTone.premika] and [ReplyTone.premik] are a different kind of entry and
/// the docs say so: the other six are ways of *saying* something, these two are
/// ways of *being* to someone - which is the one thing the prompt rules
/// otherwise forbid the model from inventing.
enum ReplyTone {
  friendly('Friendly'),
  casual('Casual'),
  professional('Professional'),
  polite('Polite'),
  funny('Funny'),
  shortAndDirect('Short and direct'),

  /// Writes as the user's girlfriend: তুমি, never আপনি.
  premika('Premika'),

  /// Writes as the user's boyfriend: তুমি, never আপনি.
  premik('Premik');

  const ReplyTone(this.label);

  final String label;

  /// True only for the two voices that ask the model to write as a partner.
  ///
  /// Everything else in this enum is a register. These two are a persona, and a
  /// persona the model invents on its own is exactly the failure the prompt
  /// rules exist to prevent - so [ReplyPrompt] keeps them opt-in, and no other
  /// tone can write as somebody the user never mentioned.
  bool get isRomantic => this == ReplyTone.premika || this == ReplyTone.premik;

  static ReplyTone fromName(String? name) => values.firstWhere(
    (tone) => tone.name == name,
    orElse: () => ReplyTone.friendly,
  );
}

enum ReplyLength {
  short('Short'),
  medium('Medium'),
  long('Long');

  const ReplyLength(this.label);

  final String label;

  static ReplyLength fromName(String? name) => values.firstWhere(
    (length) => length.name == name,
    orElse: () => ReplyLength.short,
  );
}
