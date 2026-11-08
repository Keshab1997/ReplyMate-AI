import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/providers/notification_providers.dart';
import '../models/overlay_context.dart';

/// The pending overlay context, read exactly once.
///
/// `null` means "there is nothing waiting": the native side had no pending
/// message (already consumed by another launch, or the process died between
/// posting the notification and the tap). The panel says that out loud instead
/// of rendering an empty shell (docs/FLOATING_OVERLAY.md §11).
///
/// Deliberately not auto-disposed: one panel activity, one read. Re-reading
/// would return null anyway, because the native map is cleared on read.
final FutureProvider<OverlayContext?> overlayContextProvider =
    FutureProvider<OverlayContext?>((Ref ref) async {
      final raw = await ref
          .read(notificationsBridgeProvider)
          .consumeOverlayContext();
      if (raw == null) return null;
      try {
        return OverlayContext.fromMap(Map<Object?, Object?>.from(raw));
      } on FormatException {
        // A map we cannot attribute is not shown as a message.
        return null;
      }
    });

/// The other conversations waiting behind the same bubble, as the panel's chat
/// switcher needs them. Empty whenever the native layer has nothing extra (or
/// answers nothing at all), which leaves the panel exactly as it was.
final FutureProvider<List<OverlayContext>> pendingOverlayContextsProvider =
    FutureProvider<List<OverlayContext>>((Ref ref) async {
      final raw = await ref
          .read(notificationsBridgeProvider)
          .peekOverlayContexts();
      final parsed = <OverlayContext>[];
      for (final entry in raw) {
        try {
          parsed.add(OverlayContext.fromMap(Map<Object?, Object?>.from(entry)));
        } on FormatException {
          // A map we cannot attribute is not offered as a chat.
          continue;
        }
      }
      return parsed;
    });
