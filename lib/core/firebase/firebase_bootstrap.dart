import 'dart:async';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// `google_sign_in` 7.x requires `initialize()` exactly once, and every other
/// call must wait for that future: `authenticate()` without it is documented
/// as undefined behaviour, and in practice the sign-in sheet never resolves.
///
/// Memoised so the bootstrap and the admin gate share one call — initializing
/// twice is just as undefined as not initializing at all.
Future<bool>? _googleSignInReady;

/// True once Google Sign-In is usable on this build. Safe to await anywhere:
/// the first call starts the plugin, later ones reuse its result.
Future<bool> ensureGoogleSignInReady() =>
    _googleSignInReady ??= _initializeGoogleSignIn();

Future<bool> _initializeGoogleSignIn() async {
  try {
    // No identifiers on purpose: on Android the plugin reads the web OAuth
    // client (client_type 3) out of the google-services.json the gradle
    // plugin injected. Passing serverClientId here would only add a second
    // place to keep in sync.
    await GoogleSignIn.instance.initialize();
    return true;
  } catch (error) {
    debugPrint('ReplyMate: Google sign-in is unavailable ($error)');
    return false;
  }
}

/// One-shot Firebase bootstrap with the guest-mode invariant:
///
/// - Web never initializes (the screenshot workflow and web preview must run
///   without any config file).
/// - Android initializes only when `google-services.json` is present and the
///   gradle plugin processed it; any failure flips the app into guest mode
///   instead of crashing the first frame.
///
/// When Firebase is up, the key-pool package is wired immediately so the
/// first AI call does not race the Firestore listener.
Future<bool> bootstrapFirebase() async {
  if (kIsWeb) return false;
  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('ReplyMate: Firebase not configured on this install ($error)');
    return false;
  }
  // Local plugin init, no network: start it now so the admin gate never
  // blocks on it, but do not make the first frame wait for it.
  unawaited(ensureGoogleSignInReady());
  try {
    // hive_flutter 1.x exposes this as an extension on Hive.
    await Hive.initFlutter();
    await KeyCache.init();
    ApiKeyManager.instance.initialize();
  } catch (error) {
    // Key pool unusable is not app-unusable: generation will report
    // "no healthy key" and everything else keeps working.
    debugPrint('ReplyMate: key-pool package failed to start ($error)');
  }
  return true;
}
