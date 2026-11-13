import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_providers.dart';
import 'features/reply/data/ai_budget.dart';
import 'features/reply/data/key_pool_reply_repository.dart';
import 'features/reply/data/reply_cache.dart';
import 'features/reply/data/reply_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guest-mode invariant: no config file, no network and no permission work
  // may hold the first frame hostage. Firebase either boots in milliseconds
  // or the app continues as a full guest shell.
  final firebaseReady = await bootstrapFirebase();

  // The reply cache and the daily allowance are local files, not Firebase, and
  // they wrap the provider call in both modes: guest mode still enforces the
  // budget (it just never spends it) and a cache written in one mode is not
  // served in the other unless the request is identical.
  final cache = ReplyCache(box: await _openBox(ReplyCache.openBox));
  final budget = AiBudget(box: await _openBox(AiBudget.openBox));

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        replyRepositoryProvider.overrideWithValue(
          BudgetedReplyRepository(
            inner: firebaseReady
                ? KeyPoolReplyRepository()
                : const NotConfiguredReplyRepository(),
            cache: cache,
            budget: budget,
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
