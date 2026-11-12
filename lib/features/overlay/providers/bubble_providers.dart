import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../notifications/providers/notification_providers.dart';

/// The user's "Reply bubble" switch (screen 8 of
/// ).
/// Default **off**, and off is a real answer: with the switch off neither the
/// bubble nor the fallback notification appears, so the app never nags
/// The switch only becomes usable once overlay
/// access is granted; the paid-for consequence of turning it on is a
/// foreground service, which is why it is never implied by another permission.
final NotifierProvider<BubbleEnabledNotifier, bool> bubbleEnabledProvider =
    NotifierProvider<BubbleEnabledNotifier, bool>(BubbleEnabledNotifier.new);

class BubbleEnabledNotifier extends Notifier<bool> {
  bool _alive = true;

  /// True once the user has used the switch. The stored value is loaded
  /// asynchronously, and a read that started before the tap must never land
  /// after it - that race flips the switch back to off and reads as "the
  /// switch does not work".
  bool _userChose = false;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(AppConstants.prefBubbleEnabled) ?? false;
    if (_alive && !_userChose) state = stored;
  }

  /// Persists the choice on both sides - Flutter preferences for the UI,
  /// native preferences for the listener, which runs with no engine alive -
  /// and lets the native layer start or stop the service to match.
  Future<void> setEnabled(bool enabled) async {
    _userChose = true;
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefBubbleEnabled, enabled);
    await ref.read(notificationsBridgeProvider).setBubbleEnabled(enabled);
  }
}

/// How long the bubble waits before hiding itself, in minutes; `0` means it
/// never does.
/// A setting rather than a constant because the fixed ten minutes was wrong in
/// both directions: too long for someone who wants the bubble gone the moment
/// they have answered, too short for a long conversation. Default **10
/// minutes**, which is the value the service used to hard-code, so nobody's
/// bubble changes behaviour on update.
/// Mirrored natively exactly like [bubbleEnabledProvider] - the service answers
/// this question while no Flutter engine exists, so the number has to live on
/// the native side too.
final NotifierProvider<BubbleAutoHideNotifier, int> bubbleAutoHideProvider =
    NotifierProvider<BubbleAutoHideNotifier, int>(BubbleAutoHideNotifier.new);

class BubbleAutoHideNotifier extends Notifier<int> {
  bool _alive = true;

  /// See `BubbleEnabledNotifier._userChose`: the stored value arrives late, and
  /// a read that started before the tap must never overwrite it.
  bool _userChose = false;

  @override
  int build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return AppConstants.defaultBubbleAutoHideMinutes;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = normalise(
      prefs.getInt(AppConstants.prefBubbleAutoHideMinutes),
    );
    if (_alive && !_userChose) state = stored;
  }

  Future<void> setMinutes(int minutes) async {
    _userChose = true;
    final value = normalise(minutes);
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefBubbleAutoHideMinutes, value);
    await ref.read(notificationsBridgeProvider).setBubbleAutoHideMinutes(value);
  }

  /// Keeps only the documented choices. An old build, a hand-edited
  /// preference or a future value cannot turn a ten-minute bubble into one that
  /// sits on the screen forever by accident.
  static int normalise(int? minutes) =>
      AppConstants.bubbleAutoHideOptions.contains(minutes)
      ? minutes!
      : AppConstants.defaultBubbleAutoHideMinutes;
}

/// The bubble's opt-in preview: sender + first line, drawn beside the bubble.
/// **Off by default, and the default is the point.** This is the only place
/// where message text reaches the screen outside the panel, and a bubble sitting
/// over a chat is read by whoever is next to you. People who want it can have it;
/// nobody gets it by accident.
/// What it never does, whatever this switch says: show redacted, truncated or
/// group-summary text as if it were the message (the pill says what it actually
/// has), appear on the lock screen, or write anything to disk.
final NotifierProvider<BubblePreviewNotifier, bool> bubblePreviewProvider =
    NotifierProvider<BubblePreviewNotifier, bool>(BubblePreviewNotifier.new);

class BubblePreviewNotifier extends Notifier<bool> {
  bool _alive = true;

  /// See `BubbleEnabledNotifier._userChose` for why this guard exists.
  bool _userChose = false;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        prefs.getBool(AppConstants.prefBubblePreviewEnabled) ?? false;
    if (_alive && !_userChose) state = stored;
  }

  Future<void> setEnabled(bool enabled) async {
    _userChose = true;
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefBubblePreviewEnabled, enabled);
    await ref
        .read(notificationsBridgeProvider)
        .setBubblePreviewEnabled(enabled);
  }
}
