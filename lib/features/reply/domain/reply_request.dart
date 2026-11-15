import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import 'reply_intent.dart';

/// A validated request for reply suggestions (FR-05 to FR-07).
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
    this.priorMessages = const <String>[],
    this.styleExamples = const <String>[],
    this.draftToRefine,
    this.refinementInstruction,
    this.replyIntent,
  });

  final String message;
  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;
  final int count;

  /// The lines that led up to [message], oldest first, when they were
  /// captured. Carried into the prompt so a reply answers a conversation
  /// instead of a single line pulled out of one.
  final List<String> priorMessages;

  /// Verbatim lines the user themelves sent in this conversation, newest first
  /// These are examples of a voice, never content to answer. They are stored
  /// and shown as the user's own words rather than as an inferred profile of
  /// "how this person writes", because a profile is a claim the user cannot
  /// read back and delete.
  /// Notification capture alone can never fill this: it only sees arrivals, so
  /// an empty list is the normal state with screen reading off.
  final List<String> styleExamples;

  /// Present only for a user-requested rewrite of one generated draft.
  final String? draftToRefine;

  /// A fixed, visible rewrite request such as "shorter" or "decline politely".
  final String? refinementInstruction;

  /// Optional purpose selected by the user before generating this draft.
  final ReplyIntent? replyIntent;

  String get trimmedMessage => message.trim();
  String get trimmedDraftToRefine => draftToRefine?.trim() ?? '';

  ReplyRequest copyWith({
    ReplyLanguage? language,
    ReplyTone? tone,
    ReplyLength? length,
    int? count,
    String? draftToRefine,
    String? refinementInstruction,
    ReplyIntent? replyIntent,
  }) => ReplyRequest(
    message: message,
    language: language ?? this.language,
    tone: tone ?? this.tone,
    length: length ?? this.length,
    count: count ?? this.count,
    priorMessages: priorMessages,
    styleExamples: styleExamples,
    draftToRefine: draftToRefine ?? this.draftToRefine,
    refinementInstruction: refinementInstruction ?? this.refinementInstruction,
    replyIntent: replyIntent ?? this.replyIntent,
  );

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
    if ((draftToRefine == null) != (refinementInstruction == null) ||
        (draftToRefine != null && trimmedDraftToRefine.isEmpty) ||
        (refinementInstruction != null &&
            refinementInstruction!.trim().isEmpty)) {
      problems.add('A refinement needs both a draft and a requested change.');
    }
    if (trimmedDraftToRefine.length > AppConstants.maxMessageLength) {
      problems.add('The draft to refine is too long.');
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

  Map<String, Object?> toJson() => {
    'message': trimmedMessage,
    'language': language.label,
    'tone': tone.label,
    'length': length.label,
    'count': count,
    'priorMessages': priorMessages,
    'styleExamples': styleExamples,
    if (draftToRefine != null) 'draftToRefine': trimmedDraftToRefine,
    if (refinementInstruction != null)
      'refinementInstruction': refinementInstruction,
    if (replyIntent != null) 'replyIntent': replyIntent?.name,
  };
}
