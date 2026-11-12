import '../../notifications/models/captured_notification.dart';

/// Which entry point produced the context the user is looking at.
/// `bubble` — the floating reply bubble was tapped, so the panel opens over the
/// messaging app. `fallback` — the bubble could not be shown (no overlay
/// permission, bubble switched off, or the process was cold-started in the
/// background), so the user tapped ReplyMate's own notification and the full
/// composer opens instead.
enum OverlaySource {
  bubble('bubble'),
  fallback('fallback');

  const OverlaySource(this.wireName);

  /// The value the native layer puts on the wire

  final String wireName;

  /// An unknown source is read as [fallback] on purpose: the conservative path
  /// is the full composer, which can never promise more than Android gave us
  /// and never leaves the user staring at a floating panel they cannot explain.
  static OverlaySource fromName(Object? name) => values.firstWhere(
    (source) => source.wireName == name,
    orElse: () => OverlaySource.fallback,
  );
}

/// One pending overlay context: the same notification wire format the listener
/// already emits, plus the `source` that tells the UI which screen to open.
/// Both the bubble path and the fallback path end here, so there is exactly one
/// model for "a message the user may want to reply to"
/// It is never persisted: the map it is built
/// from exists in process memory only.
class OverlayContext {
  const OverlayContext({required this.source, required this.notification});

  /// Throws [FormatException] when the map is not one of ours (no packageName,
  /// no key) - the same strictness the listener events get, for the same
  /// reason: data we cannot attribute must not be dressed up as a message.
  factory OverlayContext.fromMap(Map<Object?, Object?> map) {
    return OverlayContext(
      source: OverlaySource.fromName(map['source']),
      notification: CapturedNotification.fromMap(map),
    );
  }

  final OverlaySource source;
  final CapturedNotification notification;

  /// True when the panel (not the composer) should open.
  bool get opensPanel => source == OverlaySource.bubble;

  /// Best available name for the app the message came from: the friendly label
  /// for the messaging apps this build offers, and the package id otherwise.
  /// Never a guess dressed up as a name.
  String get appLabel =>
      _knownAppLabels[notification.packageName] ?? notification.packageName;

  /// The sender/conversation, as the notification exposed it.
  String get displayTitle => notification.displayTitle;

  String get displayText => notification.displayText;

  /// Honest one-liners about incomplete content (truncated, grouped, redacted).
  List<String> get contextWarnings => notification.contextWarnings;

  static const Map<String, String> _knownAppLabels = <String, String>{
    'com.whatsapp': 'WhatsApp',
    'org.telegram.messenger': 'Telegram',
    'com.facebook.orca': 'Messenger',
    'org.thoughtcrime.securesms': 'Signal',
    'com.google.android.apps.messaging': 'Messages',
    'com.android.mms': 'Messages',
  };

  @override
  String toString() =>
      'OverlayContext(${source.wireName}, ${notification.packageName})';
}
