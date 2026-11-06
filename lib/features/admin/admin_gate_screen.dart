import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/theme/app_theme.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/firebase/firebase_providers.dart';

/// The admin section gate (FR: admin section, batch 2).
///
/// Four honest states: Firebase not configured on this install; signed out;
/// signed in but not on the allowlist; admin. The allowlist itself lives in
/// Firestore (`admin_config/access`), so adding an admin never needs a
/// release.
class AdminGateScreen extends ConsumerWidget {
  const AdminGateScreen({super.key});

  Future<String?> _signInWithGoogle() async {
    try {
      // 7.x: initialize() must have completed before authenticate(), or the
      // flow stalls with no error at all. The bootstrap starts it; this awaits
      // the same future.
      if (!await ensureGoogleSignInReady()) {
        return 'Google sign-in is not available on this build.';
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'Google did not return an identity token.';
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      return null;
    } on GoogleSignInException catch (error) {
      // A configuration error (wrong SHA-1, wrong package, no web client) is
      // reported as `canceled` by the underlying CredentialManager SDK, so the
      // message says both instead of blaming the user for closing the sheet.
      return 'Sign-in was not completed (${error.code}). If you did not '
          'cancel it, the app\'s signing key is probably not registered in '
          'Firebase.';
    } catch (error) {
      return 'Sign-in failed: $error';
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = ref.watch(authUserProvider).value;
    final adminAccess = ref.watch(adminAccessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          children: [
            if (!firebaseReady)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spaceMd),
                  child: Text(
                    'Firebase is not configured on this install, so the '
                    'admin section is unavailable. Drop google-services.json '
                    'into android/app/ and rebuild - nothing else changes.',
                  ),
                ),
              )
            else if (user == null) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spaceMd),
                  child: Text(
                    'The admin section manages the AI key pool. Sign in with '
                    'a Google account that is on the admin allowlist '
                    '(Firestore: admin_config/access).',
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              FilledButton.icon(
                onPressed: () async {
                  final problem = await _signInWithGoogle();
                  if (problem != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(problem)));
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed in as ${user.email ?? user.uid}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppTheme.spaceSm),
                      adminAccess.when(
                        data: (isAdmin) => isAdmin
                            ? const Text(
                                'This account is on the admin allowlist.',
                              )
                            : const Text(
                                'This account is NOT on the admin allowlist. '
                                'Ask an admin to add its email or uid to '
                                'admin_config/access in Firestore.',
                              ),
                        loading: () => const Text('Checking admin access…'),
                        error: (_, _) =>
                            const Text('Could not read the admin allowlist.'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              if (adminAccess.value == true)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminApiKeysScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Open API key manager'),
                ),
              const SizedBox(height: AppTheme.spaceSm),
              OutlinedButton.icon(
                onPressed: () => _signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
