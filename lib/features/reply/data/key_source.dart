import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Indirection over the key pool so the repository stays unit-testable:
/// tests inject a fake instead of the Firestore-backed singleton.
abstract interface class KeySource {
  AdminApiKey? next();
  void reportSuccess(AdminApiKey key);
  void reportFailure(AdminApiKey key, int statusCode);
}

/// Production implementation: the admin_api_key_manager pool with its
/// failover, cooldowns and health checks.
class ApiKeyManagerKeySource implements KeySource {
  const ApiKeyManagerKeySource();

  @override
  AdminApiKey? next() => ApiKeyManager.instance.getNextKey();

  @override
  void reportSuccess(AdminApiKey key) =>
      ApiKeyManager.instance.reportSuccess(key);

  @override
  void reportFailure(AdminApiKey key, int statusCode) =>
      ApiKeyManager.instance.reportFailure(
        key,
        statusCode,
        'reply_generation',
        FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
      );
}
