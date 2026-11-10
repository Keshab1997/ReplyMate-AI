import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../notifications/providers/notification_providers.dart';

/// The user's "Read the open chat" switch (docs/SCREEN_READING.md).
///
/// Default **off**, and off is a real answer. Screen reading is a bigger ask
/// than notification access: it is the one feature here that can see text the
/// platform never hands us, so it is never implied by another permission and
/// never switched on unless the user says so on this switch.
///
/// The switch and the Android setting are two separate things and the UI says
/// so: Android grants accessibility access in its own Settings screen, and
/// this switch then decides whether ReplyMate uses it. With Android 16+
/// Advanced Protection Mode on, the system refuses the grant altogether for an
/// app it does not classify as an accessibility tool - ReplyMate is not one
/// and does not pretend to be, so on such a device this switch stays off and
/// [screenReadingAvailableProvider] says why.
final NotifierProvider<ScreenReadingNotifier, bool> screenReadingProvider =
    NotifierProvider<ScreenReadingNotifier, bool>(ScreenReadingNotifier.new);

class ScreenReadingNotifier extends Notifier<bool> {
  bool _alive = true;

  /// True once the user has used the switch - see the race described in
  /// `bubble_providers.dart`, which this mirrors exactly.
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
        prefs.getBool(AppConstants.prefScreenReadingEnabled) ?? false;
    if (_alive && !_userChose) state = stored;
  }

  /// Persists the choice on both sides - Flutter preferences for the UI,
  /// native preferences for the accessibility service, which runs with no
  /// engine alive.
  Future<void> setEnabled(bool enabled) async {
    _userChose = true;
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefScreenReadingEnabled, enabled);
    await ref
        .read(notificationsBridgeProvider)
        .setScreenReadingEnabled(enabled);
  }
}

/// Whether Android has actually granted accessibility access.
///
/// Re-read on resume: the user grants it on a system screen that covers the
/// app, so the value the switch was built with is stale the moment they come
/// back - the same fix the overlay switch needed.
final NotifierProvider<ScreenReadingAvailabilityNotifier, bool>
screenReadingAvailableProvider =
    NotifierProvider<ScreenReadingAvailabilityNotifier, bool>(
      ScreenReadingAvailabilityNotifier.new,
    );

class ScreenReadingAvailabilityNotifier extends Notifier<bool> {
  bool _alive = true;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return false;
  }

  Future<void> _load() async {
    final available = await ref
        .read(notificationsBridgeProvider)
        .isScreenReadingAvailable();
    if (_alive) state = available;
  }

  Future<void> refresh() => _load();
}
