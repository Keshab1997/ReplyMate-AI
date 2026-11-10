/// One notification's worth of message context, exactly as the native parser
/// delivered it.
///
/// Mirrors the `notification_captured` wire format in
/// docs/PLATFORM_CHANNELS.md. The constructor is deliberately strict about
/// structure (a missing packageName or key means the event is not from our
/// native layer and must not be trusted) and deliberately lenient about
/// content (FR-04: missing, truncated, grouped or redacted text is a normal
/// state, not an error).
class CapturedNotification {
  const CapturedNotification({
    required this.packageName,
    required this.key,
    this.title,
    this.text,
    required this.isTruncated,
    required this.isGrouped,
    required this.isGroupSummary,
    required this.mayBeRedacted,
    required this.hasReplyAction,
    this.replyActionLabel,
    required this.postedAtMillis,
    this.isScreenRead = false,
  });

  factory CapturedNotification.fromMap(Map<Object?, Object?> map) {
    final packageName = map['packageName'];
    final key = map['key'];
    if (packageName is! String || packageName.isEmpty) {
      throw const FormatException('notification event without packageName');
    }
    if (key is! String || key.isEmpty) {
      throw const FormatException('notification event without key');
    }
    final title = map['title'];
    final text = map['text'];
    final replyActionLabel = map['replyActionLabel'];
    final postedAt = map['postedAtMillis'];
    return CapturedNotification(
      packageName: packageName,
      key: key,
      title: title is String ? title : null,
      text: text is String ? text : null,
      isTruncated: map['isTruncated'] == true,
      isGrouped: map['isGrouped'] == true,
      isGroupSummary: map['isGroupSummary'] == true,
      mayBeRedacted: map['mayBeRedacted'] == true,
      hasReplyAction: map['hasReplyAction'] == true,
      replyActionLabel: replyActionLabel is String ? replyActionLabel : null,
      postedAtMillis: postedAt is int ? postedAt : 0,
      isScreenRead: map['fromScreen'] == true,
    );
  }

  final String packageName;

  /// Android's StatusBarNotification key; identifies the notification for
  /// quick reply and deduplication.
  final String key;
  final String? title;
  final String? text;
  final bool isTruncated;
  final bool isGrouped;
  final bool isGroupSummary;
  final bool mayBeRedacted;
  final bool hasReplyAction;
  final String? replyActionLabel;
  final int postedAtMillis;

  /// True when this text was read off the screen rather than delivered by a
  /// notification (docs/SCREEN_READING.md). It is not a warning and not a
  /// problem - it is a fact the UI says out loud, because "where did this
  /// message come from" is exactly the question a privacy-first app owes an
  /// answer to.
  final bool isScreenRead;

  bool get hasText => (text ?? '').trim().isNotEmpty;

  /// What the composer shows as the message being replied to. A notification
  /// without usable text is still shown, but as "content unavailable" -
  /// never as an empty quote that looks like a bug.
  String get displayText => hasText ? text!.trim() : '';

  String get displayTitle {
    if ((title ?? '').trim().isNotEmpty) return title!.trim();
    return packageName;
  }

  /// Honest one-line summary of why this context may be incomplete; empty
  /// when nothing is wrong.
  ///
  /// The flags on the wire are literal facts about the notification; this list
  /// is the *judgement* about which ones the user can act on. Two of them are
  /// noisy on their own:
  ///  - `isGrouped` is true for any notification carrying a group key, and
  ///    WhatsApp sets one for every ordinary chat, so only a group *summary*
  ///    (stacked messages, where the text really is a digest) is reported;
  ///  - `mayBeRedacted` only matters when no text arrived - if the text is
  ///    here, nothing was hidden from us.
  ///
  /// Warning about everything all the time trains the user to ignore the
  /// warning that does matter (docs/FLOATING_OVERLAY.md §3 rule 7).
  List<String> get contextWarnings {
    final warnings = <String>[];
    if (!hasText) {
      warnings.add('no message text available');
      if (mayBeRedacted) warnings.add('may be redacted by privacy settings');
    }
    if (isTruncated) warnings.add('text may be truncated');
    if (isGroupSummary) warnings.add('grouped notification');
    return warnings;
  }

  @override
  String toString() =>
      'CapturedNotification($packageName, key=$key, text=$hasText, '
      'replyAction=$hasReplyAction, screen=$isScreenRead)';
}
