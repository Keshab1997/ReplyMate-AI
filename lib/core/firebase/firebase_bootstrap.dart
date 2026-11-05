import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
