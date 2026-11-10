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

  /// The user's bubble switch. Mirrored natively (same meaning, native prefs)
  /// because the notification listener must read it while no Flutter engine is
  /// alive (docs/FLOATING_OVERLAY.md §5.3).
  static const String prefBubbleEnabled = 'replymate.bubble_enabled';

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
}
