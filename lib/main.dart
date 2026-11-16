import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_providers.dart';

import 'features/reply/data/ai_usage_tracker.dart';
import 'features/reply/data/own_key_reply_repository.dart';
import 'features/reply/data/own_key_store.dart';
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
  final ownKeyBox = await _openBox(OwnKeyStore.openBox);
  final ownKeys = OwnKeyStore(box: ownKeyBox);

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        replyRepositoryProvider.overrideWithValue(
          CachedReplyRepository(
            // A key the user pasted is tried first: it is theirs, it cannot
            // leak from Firestore, and it is the only path that works with no
            // Firebase project at all. `generate` returns a failure when no key
            // is set, and the wrapper then falls back to offline suggestions.
            inner: ownKeys.hasKey
                ? OwnKeyReplyRepository(keys: ownKeys)
                : firebaseReady
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
