import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';

/// A validated request for reply suggestions (FR-05 to FR-07).
///
/// Validation lives in the domain layer so every entry point - composer,
/// PROCESS_TEXT, share sheet - gets the same guarantees, and so the rules are
/// unit-testable without widgets.
class ReplyRequest {
  const ReplyRequest({
    required this.message,
    required this.language,
    required this.tone,
    required this.length,
    this.count = 3,
  });

  final String message;
  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;
  final int count;

  String get trimmedMessage => message.trim();

  /// All problems with this request, empty when it is sendable. Returning a
  /// list (not the first error) lets the UI show everything at once instead
  /// of playing whack-a-mole with the user.
  List<String> validate() {
    final problems = <String>[];
    if (trimmedMessage.isEmpty) {
      problems.add('Add a message or paste the text you want to reply to.');
    } else if (trimmedMessage.length > AppConstants.maxMessageLength) {
      problems.add(
        'Message is too long (${trimmedMessage.length} characters, '
        'limit ${AppConstants.maxMessageLength}).',
      );
    }
    if (count < AppConstants.minSuggestionCount ||
        count > AppConstants.maxSuggestionCount) {
      problems.add(
        'Suggestion count must be between '
        '${AppConstants.minSuggestionCount} and '
        '${AppConstants.maxSuggestionCount}.',
      );
    }
    return problems;
  }

  bool get isValid => validate().isEmpty;

  /// Wire shape for the future backend / key-manager call
  /// (docs/AI_INTEGRATION.md example request).
  Map<String, Object?> toJson() => {
    'message': trimmedMessage,
    'language': language.label,
    'tone': tone.label,
    'length': length.label,
    'count': count,
  };
}
