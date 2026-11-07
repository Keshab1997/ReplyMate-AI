import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../notifications/providers/notification_providers.dart';

/// The user's "Reply bubble" switch (screen 8 of
/// docs/SCREEN_SPECIFICATIONS.md).
///
/// Default **off**, and off is a real answer: with the switch off neither the
/// bubble nor the fallback notification appears, so the app never nags
/// (docs/FLOATING_OVERLAY.md §8). The switch only becomes usable once overlay
/// access is granted; the paid-for consequence of turning it on is a
/// foreground service, which is why it is never implied by another permission.
final NotifierProvider<BubbleEnabledNotifier, bool> bubbleEnabledProvider =
    NotifierProvider<BubbleEnabledNotifier, bool>(BubbleEnabledNotifier.new);

class BubbleEnabledNotifier extends Notifier<bool> {
  bool _alive = true;

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
    if (_alive) state = stored;
  }

  /// Persists the choice on both sides - Flutter preferences for the UI,
  /// native preferences for the listener, which runs with no engine alive -
  /// and lets the native layer start or stop the service to match.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefBubbleEnabled, enabled);
    await ref.read(notificationsBridgeProvider).setBubbleEnabled(enabled);
  }
}
