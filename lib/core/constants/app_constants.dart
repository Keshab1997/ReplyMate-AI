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
  static const String prefSelectedApps = 'replymate.selected_apps';
  static const String prefDefaultLanguage = 'replymate.default_language';
  static const String prefDefaultTone = 'replymate.default_tone';
  static const String prefDefaultLength = 'replymate.default_length';

  /// The user's bubble switch. Mirrored natively (same meaning, native prefs)
  /// because the notification listener must read it while no Flutter engine is
  /// alive (docs/FLOATING_OVERLAY.md §5.3).
  static const String prefBubbleEnabled = 'replymate.bubble_enabled';

  /// Hard ceiling on a message we will send to an AI provider (FR-10: fail
  /// with a clear error instead of an oversized request).
  static const int maxMessageLength = 4000;

  /// Suggestion count bounds offered by the composer.
  static const int minSuggestionCount = 1;
  static const int maxSuggestionCount = 3;
}
