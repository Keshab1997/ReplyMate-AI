import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_providers.dart';

import 'features/reply/data/ai_usage_tracker.dart';
import 'features/reply/data/key_pool_reply_repository.dart';
import 'features/reply/data/reply_cache.dart';
import 'features/reply/data/reply_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guest-mode invariant: no config file, no network and no permission work
  // may hold the first frame hostage. Firebase either boots in milliseconds
  // or the app continues as a full guest shell.
  final firebaseReady = await bootstrapFirebase();

  // The reply cache and local usage counter are not Firebase-backed. A cache
  // written in one mode is not served in the other unless the request matches.
  // Usage is informational only and never limits paid provider calls.
  final cache = ReplyCache(box: await _openBox(ReplyCache.openBox));
  final usage = AiUsageTracker(box: await _openBox(AiUsageTracker.openBox));

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        replyRepositoryProvider.overrideWithValue(
          CachedReplyRepository(
            // Every AI call goes through the admin key pool: one place decides
            // which key is healthy, one place rotates it, and no key belongs to
            // the device. With no Firebase project there is no pool to read, so
            // the honest answer is "not configured" and the wrapper still falls
            // back to offline suggestions.
            inner: firebaseReady
                ? KeyPoolReplyRepository()
                : const NotConfiguredReplyRepository(),
            cache: cache,
            usageTracker: usage,
          ),
        ),
      ],
      child: const ReplyMateApp(),
    ),
  );
}

/// Hive boxes are opened best-effort: a box that fails to open turns the
/// feature off rather than stopping the app, which is the same rule the app
/// already applies to Firebase.
Future<T?> _openBox<T>(Future<T> Function() open) async {
  try {
    return await open();
  } catch (_) {
    return null;
  }
}
