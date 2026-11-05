import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_providers.dart';
import 'features/reply/data/key_pool_reply_repository.dart';
import 'features/reply/data/reply_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guest-mode invariant: no config file, no network and no permission work
  // may hold the first frame hostage. Firebase either boots in milliseconds
  // or the app continues as a full guest shell.
  final firebaseReady = await bootstrapFirebase();

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        if (firebaseReady)
          replyRepositoryProvider.overrideWithValue(KeyPoolReplyRepository()),
      ],
      child: const ReplyMateApp(),
    ),
  );
}
