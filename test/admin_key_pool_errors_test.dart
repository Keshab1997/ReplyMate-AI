import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app pins the admin package by commit, so the one thing worth asserting
/// here is that the pin actually brings the fix in: a `permission-denied` read
/// has to be classified, and the app's own admin screen has to be able to
/// render the instruction. If the pin is ever rolled back, this test says so
/// before a device does.
void main() {
  test('the pinned admin package classifies a permission-denied read', () {
    expect(
      classifyKeyPoolError(
        '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
      ),
      KeyPoolFailure.permissionDenied,
    );
  });

  test('the instruction names the Firestore document an admin must edit', () {
    final copy = describeKeyPoolFailure(KeyPoolFailure.permissionDenied);
    expect(copy.title, isNotEmpty);
    expect(copy.detail, contains('admin_config/access'));
  });

  test('a missing Firebase is not reported as a permission problem', () {
    // Guest builds have no google-services.json; that must never look like a
    // broken allowlist, or the advice sends the user to the wrong fix.
    expect(
      classifyKeyPoolError(
        'FirebaseException: [core/no-app] No Firebase App "[DEFAULT]" has been '
        'created - call Firebase.initializeApp()',
      ),
      KeyPoolFailure.notConfigured,
    );
  });
}
