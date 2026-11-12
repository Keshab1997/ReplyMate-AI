/// Names shared between the Dart and native layers, and preference keys.
///
/// The channel contract itself is documented in docs/PLATFORM_CHANNELS.md.
class AppConstants {
  AppConstants._();

  /// Single MethodChannel for Dart -> Kotlin calls; Kotlin -> Dart events
  /// arrive on the same channel as `onEvent` method calls.
  static const String channelName = 'com.keshabstudios.replymate/notifications';

  /// SharedPreferences keys (all prefixed to stay obvious in debugging).
  static const String prefOnboardingDone = 'replymate.onboarding_done';

  /// Interface language ('en' / 'bn'). Independent of the reply language: a
  /// Bengali UI can draft English replies.
  static const String prefAppLanguage = 'replymate.app_language';
  static const String prefSelectedApps = 'replymate.selected_apps';
  static const String prefDefaultLanguage = 'replymate.default_language';
  static const String prefDefaultTone = 'replymate.default_tone';
  static const String prefDefaultLength = 'replymate.default_length';

  /// How many replies the app drafts at once. One is the default: comparing
  /// three paragraphs is more work than editing the one you would have picked
  /// anyway, and it costs three times the tokens.
  static const String prefSuggestionCount = 'replymate.suggestion_count';

  /// The user's bubble switch. Mirrored natively (same meaning, native prefs)
  /// because the notification listener must read it while no Flutter engine is
  /// alive (docs/FLOATING_OVERLAY.md §5.3).
  static const String prefBubbleEnabled = 'replymate.bubble_enabled';

  /// How long the bubble waits before hiding itself, in minutes, mirrored
  /// natively for the same reason as the switch above: the service reads it
  /// while no engine is alive. `0` means it never hides itself, and a value the
  /// service does not recognise falls back to the documented default rather
  /// than to "never" - the quieter of the two honest answers
  /// (docs/FLOATING_OVERLAY.md §5.4).
  static const String prefBubbleAutoHideMinutes =
      'replymate.bubble_auto_hide_minutes';

  /// The user's "Show a preview" switch: the sender and first line, beside the
  /// bubble. Mirrored natively like the bubble switch, and **off by default** -
  /// a bubble over a chat is read by whoever is next to you
  /// (docs/FLOATING_OVERLAY.md §5.6).
  static const String prefBubblePreviewEnabled =
      'replymate.bubble_preview_enabled';

  /// The auto-hide choices the settings screen offers, in minutes. Ten is the
  /// original fixed value, so an existing user is not moved by the update.
  static const List<int> bubbleAutoHideOptions = <int>[5, 10, 30, 0];

  /// Ten minutes: long enough to answer the message you were pinged about,
  /// short enough that a forgotten bubble does not sit there all afternoon.
  static const int defaultBubbleAutoHideMinutes = 10;

  /// The user's screen-reading switch (docs/SCREEN_READING.md). Mirrored
  /// natively for the same reason as the bubble switch: the accessibility
  /// service must read it at a moment when no Flutter engine is alive.
  static const String prefScreenReadingEnabled =
      'replymate.screen_reading_enabled';

  /// Hard ceiling on a message we will send to an AI provider (FR-10: fail
  /// with a clear error instead of an oversized request).
  static const int maxMessageLength = 4000;

  /// Suggestion count bounds offered by the composer.
  static const int minSuggestionCount = 1;
  static const int maxSuggestionCount = 3;

  static const int defaultSuggestionCount = 1;
}
