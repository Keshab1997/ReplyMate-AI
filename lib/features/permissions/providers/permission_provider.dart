import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/providers/notification_providers.dart';

/// Notification-listener access state (FR-02).
///
/// Starts at false and refreshes from the native layer; native events keep it
/// honest while the app is open (Android can revoke access from Settings at
/// any time, docs/USER_FLOWS flow 4).
final NotifierProvider<PermissionNotifier, bool> listenerPermissionProvider =
    NotifierProvider<PermissionNotifier, bool>(PermissionNotifier.new);

class PermissionNotifier extends Notifier<bool> {
  bool _alive = true;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    // Fire-and-forget initial read; the UI shows the real value as soon as
    // the native layer answers.
    refresh();
    return false;
  }

  Future<void> refresh() async {
    final enabled = await ref
        .read(notificationsBridgeProvider)
        .isListenerEnabled();
    if (_alive) state = enabled;
  }

  Future<void> openSettings() =>
      ref.read(notificationsBridgeProvider).openListenerSettings();

  /// Called by the event stream when the listener connects or disconnects.
  void markConnected(bool connected) {
    state = connected;
  }
}

/// "Display over other apps" state, for the floating reply bubble
/// (docs/FLOATING_OVERLAY.md §6).
///
/// A separate provider on purpose: overlay access is its own grant, is
/// revocable on its own, and must never be inferred from - or imply -
/// notification access.
final NotifierProvider<OverlayPermissionNotifier, bool> overlayProvider =
    NotifierProvider<OverlayPermissionNotifier, bool>(
      OverlayPermissionNotifier.new,
    );

class OverlayPermissionNotifier extends Notifier<bool> {
  bool _alive = true;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    refresh();
    return false;
  }

  /// Re-reads the grant. Called at startup, when the app resumes (the user may
  /// have granted or revoked it in Settings), and after the Settings screen
  /// was opened.
  Future<void> refresh() async {
    final enabled = await ref
        .read(notificationsBridgeProvider)
        .isOverlayEnabled();
    if (_alive) state = enabled;
  }

  /// Opens Android's overlay screen; the permission screen re-reads on resume.
  Future<void> openSettings() =>
      ref.read(notificationsBridgeProvider).openOverlaySettings();
}
