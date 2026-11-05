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

/// All six tones from PRODUCT_REQUIREMENTS.md FR-06. The README's marketing
/// list shows five; the requirement document is the source of truth.
enum ReplyTone {
  friendly('Friendly'),
  casual('Casual'),
  professional('Professional'),
  polite('Polite'),
  funny('Funny'),
  shortAndDirect('Short and direct');

  const ReplyTone(this.label);

  final String label;

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
