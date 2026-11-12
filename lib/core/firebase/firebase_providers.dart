import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True only when Firebase.initializeApp succeeded at startup. Overridden in
/// main(); every Firebase-touching provider reads this first so guest mode
/// has a single source of truth.
final Provider<bool> firebaseReadyProvider = Provider<bool>((Ref ref) => false);

/// The signed-in user, or null in guest mode / when signed out.
final StreamProvider<User?> authUserProvider = StreamProvider<User?>((Ref ref) {
  if (!ref.watch(firebaseReadyProvider)) return Stream<User?>.value(null);
  return FirebaseAuth.instance.authStateChanges();
});

/// The admin gate: a Firestore allowlist doc decides who may open the API-key
/// manager.
/// Doc: `admin_config/access` with either (or both) of:
///   { "emails": ["keshab@example.com"], "uids": ["<firebase uid>"] }
/// Emails make the list editable without knowing uids; uids survive an email
/// change. Anything missing, unreadable or denied resolves to false - the
/// admin section hides instead of erroring.
final FutureProvider<bool> adminAccessProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) return false;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('admin_config')
        .doc('access')
        .get();
    final data = doc.data() ?? const <String, Object?>{};
    final emails =
        (data['emails'] as List?)?.whereType<String>().toSet() ??
        const <String>{};
    final uids =
        (data['uids'] as List?)?.whereType<String>().toSet() ??
        const <String>{};
    final email = user.email;
    return (email != null && emails.contains(email)) || uids.contains(user.uid);
  } catch (error) {
    // No rules, no doc, offline: not an admin, no crash.
    return false;
  }
});
