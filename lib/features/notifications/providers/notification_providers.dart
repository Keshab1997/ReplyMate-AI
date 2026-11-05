import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/notifications_bridge.dart';
import '../../permissions/providers/permission_provider.dart';
import '../models/captured_notification.dart';
import '../models/launch_context.dart';

/// The one bridge instance for the whole app. Created lazily, disposed with
/// the container (tests dispose it via `ProviderContainer.dispose`).
final Provider<NotificationsBridge> notificationsBridgeProvider =
    Provider<NotificationsBridge>((Ref ref) {
      final bridge = NotificationsBridge();
      bridge.startListening();
      ref.onDispose(bridge.dispose);
      return bridge;
    });

/// Raw native events, for screens that need to react to connectivity changes.
final StreamProvider<Map<String, Object?>> notificationEventsProvider =
    StreamProvider<Map<String, Object?>>(
      (Ref ref) => ref.watch(notificationsBridgeProvider).events,
    );

/// Captured message contexts, newest first, capped so a chatty device never
/// grows an unbounded list of other people's messages in memory.
final StateNotifierProvider<
  CapturedNotificationsNotifier,
  List<CapturedNotification>
>
capturedNotificationsProvider =
    StateNotifierProvider<
      CapturedNotificationsNotifier,
      List<CapturedNotification>
    >((Ref ref) => CapturedNotificationsNotifier(ref));

class CapturedNotificationsNotifier
    extends StateNotifier<List<CapturedNotification>> {
  CapturedNotificationsNotifier(this._ref)
    : super(const <CapturedNotification>[]) {
    _subscription = _ref
        .read(notificationsBridgeProvider)
        .events
        .listen(_onEvent);
  }

  static const int _maxRetained = 20;

  final Ref _ref;
  late final StreamSubscription<Map<String, Object?>> _subscription;

  void _onEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'listener_connected':
        _ref.read(listenerPermissionProvider.notifier).markConnected(true);
      case 'listener_disconnected':
        _ref.read(listenerPermissionProvider.notifier).markConnected(false);
      case 'notification_captured':
        final payload = event['notification'];
        if (payload is! Map) return;
        try {
          final captured = CapturedNotification.fromMap(
            Map<Object?, Object?>.from(payload),
          );
          state = <CapturedNotification>[
            captured,
            ...state.where((existing) => existing.key != captured.key),
          ].take(_maxRetained).toList();
        } on FormatException {
          // An event that does not match our own wire format is ignored
          // rather than trusted (validate all incoming native data).
        }
      default:
        break;
    }
  }

  void clear() => state = const <CapturedNotification>[];

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Text delivered by PROCESS_TEXT / ACTION_SEND, consumed once at startup.
final FutureProvider<LaunchContext?> launchContextProvider =
    FutureProvider<LaunchContext?>((Ref ref) async {
      final raw = await ref
          .read(notificationsBridgeProvider)
          .consumeLaunchContext();
      if (raw == null) return null;
      final context = LaunchContext.fromMap(raw);
      return context.hasText ? context : null;
    });
