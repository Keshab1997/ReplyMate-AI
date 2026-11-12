import 'dart:async';

import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../../features/screen_reading/models/screen_reading_status.dart';

/// A messaging app the native layer can actually see installed.
class CandidateApp {
  const CandidateApp({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

/// Dart half of the single platform channel. Every method degrades to a safe
/// empty answer when the plugin is missing (tests, web preview, desktop) so
/// the UI can render and explain instead of crashing.
///
/// Contract: docs/PLATFORM_CHANNELS.md.
class NotificationsBridge {
  NotificationsBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(AppConstants.channelName);

  final MethodChannel _channel;
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();

  /// Native -> Dart events: `listener_connected`, `listener_disconnected`,
  /// `notification_captured` (a notification arrived) and `screen_captured`
  /// (a message was read off the screen, docs/SCREEN_READING.md). Both carry
  /// the same `notification` payload, so both are parsed by
  /// `CapturedNotification`.
  Stream<Map<String, Object?>> get events => _events.stream;

  /// Starts forwarding `onEvent` calls into [events]. Idempotent.
  void startListening() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEvent' && call.arguments is Map) {
        _events.add(Map<String, Object?>.from(call.arguments as Map));
      }
      return null;
    });
  }

  Future<bool> isListenerEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isListenerEnabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openListenerSettings() async {
    try {
      await _channel.invokeMethod<void>('openListenerSettings');
    } on MissingPluginException {
      // No native layer (tests / web): nothing to open.
    }
  }

  Future<List<CandidateApp>> candidateApps() async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'candidateApps',
      );
      if (result == null) return const [];
      return result
          .whereType<Map<Object?, Object?>>()
          .map(
            (map) => CandidateApp(
              packageName: map['packageName'] as String? ?? '',
              label: map['label'] as String? ?? '',
            ),
          )
          .where((app) => app.packageName.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const [];
    }
  }

  /// Pushes the user's app selection down to the native listener, which only
  /// processes packages on this list.
  Future<void> setAllowedPackages(List<String> packages) async {
    try {
      await _channel.invokeMethod<void>('setAllowedPackages', {
        'packages': packages,
      });
    } on MissingPluginException {
      // Native layer absent: the selection still persists on the Dart side.
    }
  }

  /// Attempts a RemoteInput quick reply against the notification identified
  /// by [notificationKey] (its `StatusBarNotification.key`). False means "no
  /// valid action, the action is no longer live, or the notification is not
  /// the one being replied to" - the UI must then offer copy / open-app
  /// (docs/USER_FLOWS flow 3).
  ///
  /// The key travels with the call on purpose: a reply must only ever reach
  /// the conversation it was written for.
  Future<bool> sendQuickReply(
    String text, {
    required String notificationKey,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('sendQuickReply', {
            'text': text,
            'key': notificationKey,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens Android's system share sheet for a user-selected reply. The
  /// return value means only that the chooser opened; the user still chooses
  /// the destination and confirms any send action.
  Future<bool> shareText(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('shareText', {'text': text}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Clears native notification context retained only for a possible reply
  /// during the current composer session.
  Future<void> clearRetainedContext() async {
    try {
      await _channel.invokeMethod<void>('clearRetainedContext');
    } on MissingPluginException {
      // No native layer (tests / web): nothing is retained there.
    } on PlatformException {
      // Cleanup is best-effort; the Dart-side buffer is cleared separately.
    }
  }

  /// True when Android lets this app draw over other apps. Overlay access is
  /// optional and never implied by notification access
  /// (docs/PRIVACY_AND_PERMISSIONS.md).
  Future<bool> isOverlayEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isOverlayEnabled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Android's "Display over other apps" screen for this app. Grants
  /// nothing by itself - the decision stays in Settings, like every other
  /// permission here.
  Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } on MissingPluginException {
      // No native layer (tests / web): nothing to open.
    } on PlatformException {
      // Some OEMs hide the screen; the permission card keeps saying
      // "not granted", which is the truth.
    }
  }

  /// Asks for the Android 13+ notification runtime permission. `true` below
  /// API 33 and when it was granted earlier; `false` means the user said no,
  /// and the UI says so instead of pretending notifications will appear.
  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Persists the bubble switch natively and starts/stops the bubble service.
  ///
  /// Persisted rather than held in memory because the notification listener
  /// reads it with no Flutter engine alive. Starting the service can be
  /// refused by Android 12+ when the app is in the background; that is caught
  /// natively and surfaced as the fallback notification, not a crash.
  Future<void> setBubbleEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setBubbleEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // No native layer: the Dart-side preference still records the choice.
    } on PlatformException {
      // Surfaced by the service's own state, never by a crash.
    }
  }

  /// How long the bubble lingers without being used, in minutes. Mirrored
  /// natively for the same reason as the switch: the service has to answer this
  /// with no engine alive. `0` is a real answer meaning "never hide yourself".
  Future<void> setBubbleAutoHideMinutes(int minutes) async {
    try {
      await _channel.invokeMethod<void>('setBubbleAutoHideMinutes', {
        'minutes': minutes,
      });
    } on MissingPluginException {
      // No native layer: the Dart-side preference still records the choice.
    } on PlatformException {
      // Surfaced by the bubble's own behaviour, never by a crash.
    }
  }

  /// True when Android has granted ReplyMate accessibility access, which is
  /// the only way the screen reader can run at all. False on a device that
  /// refuses it - Android 16+ Advanced Protection does exactly that for an app
  /// it does not classify as an accessibility tool, and ReplyMate does not
  /// claim to be one (docs/SCREEN_READING.md).
  Future<bool> isScreenReadingAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isScreenReadingAvailable') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// What the screen reader did on its last look at the screen.
  ///
  /// Null when there is nothing to report - no native layer, or a build with no
  /// screen reader at all. Every field inside is allowed to be empty: a reader
  /// that has never run is a normal state, not an error.
  Future<ScreenReadingStatus?> screenReadingStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'screenReadingStatus',
      );
      if (raw == null) return null;
      return ScreenReadingStatus.fromMap(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Opens Android's accessibility settings, on ReplyMate's own page when the
  /// device supports it. Like every permission here, this opens a screen and
  /// grants nothing by itself.
  ///
  /// Returns which screen actually opened: `details` (ReplyMate's own toggle),
  /// `list` (the general accessibility list), or `none` (this device has no
  /// such screen). The UI says which, so a phone that cannot open the page is
  /// never described as though it could.
  Future<String> openAccessibilitySettings() async {
    try {
      return await _channel.invokeMethod<String>('openAccessibilitySettings') ??
          'none';
    } on MissingPluginException {
      return 'none';
    } on PlatformException {
      return 'none';
    }
  }

  /// Persists the screen-reading switch natively as well, because the
  /// accessibility service runs with no Flutter engine alive.
  Future<void> setScreenReadingEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setScreenReadingEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // No native layer: the Dart-side preference still records the choice.
    } on PlatformException {
      // Surfaced by the switch's own state, never by a crash.
    }
  }

  /// The pending overlay context - `{source, packageName, key, title, text, ...}`
  /// - consumed once. `source` is `bubble` or `fallback`; every other field is
  /// the `notification_captured` wire format, so `CapturedNotification` parses
  /// it unchanged (docs/PLATFORM_CHANNELS.md).
  ///
  /// One-shot by contract, not by convention: the native side clears the
  /// pending map as it answers, so a second call returns null rather than
  /// handing the same message out twice.
  Future<Map<Object?, Object?>?> consumeOverlayContext() async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>(
        'consumeOverlayContext',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Asks the native layer to close the panel activity.
  ///
  /// The panel cannot close itself with a Navigator pop: it is the only route
  /// in its own activity, and popping it used to reveal the main app behind
  /// it. Finishing the activity puts the user back in the chat they came from.
  /// Returns false when there is no native layer to ask (in-app preview, tests).
  Future<bool> closeOverlayPanel() async {
    try {
      await _channel.invokeMethod<void>('closeOverlayPanel');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Every message currently waiting behind the bubble, newest first.
  ///
  /// Read-only: unlike [consumeOverlayContext] this removes nothing, so the
  /// panel's chat switcher can name the other conversations without eating the
  /// one the bubble is already showing. A native layer that does not know the
  /// method answers with an empty list, which is the honest answer.
  Future<List<Map<Object?, Object?>>> peekOverlayContexts() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'peekOverlayContexts',
      );
      return raw ?? const <Map<Object?, Object?>>[];
    } on MissingPluginException {
      return const <Map<Object?, Object?>>[];
    } on PlatformException {
      return const <Map<Object?, Object?>>[];
    }
  }

  /// Text handed over by PROCESS_TEXT or ACTION_SEND, consumed once.
  Future<LaunchContextMap?> consumeLaunchContext() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'consumeLaunchContext',
      );
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _events.close();
  }
}

/// Raw map shape of a launch context; parsed into `LaunchContext` by callers.
typedef LaunchContextMap = Map<Object?, Object?>;
