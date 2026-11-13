import 'package:hive_flutter/hive_flutter.dart';

/// A personal provider key, as the user entered it.
class OwnKey {
  const OwnKey({
    required this.key,
    required this.provider,
    required this.baseUrl,
    required this.model,
  });

  final String key;
  final String provider;
  final String baseUrl;
  final String model;

  Map<String, dynamic> toMap() => {
    'key': key,
    'provider': provider,
    'baseUrl': baseUrl,
    'model': model,
  };

  static OwnKey? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'] as String? ?? '';
    if (key.trim().isEmpty) return null;
    return OwnKey(
      key: key,
      provider: raw['provider'] as String? ?? 'openrouter',
      baseUrl: raw['baseUrl'] as String? ?? '',
      model: raw['model'] as String? ?? '',
    );
  }
}

/// Where the user's own key lives: **this device, and nowhere else.**
///
/// That sentence is the whole security model of the feature. The key is not
/// written to Firestore, not logged, not sent anywhere except the provider the
/// user chose, and `android:allowBackup` stays false so no cloud backup carries
/// it off the phone.
///
/// It is also the reason the app can work with no Firebase project at all:
/// there is nothing to configure, no admin pool to read, no rules to get right.
class OwnKeyStore {
  OwnKeyStore({this.box});

  static const String boxName = 'own_key';
  static const String _keyName = 'own_key';

  final Box<dynamic>? box;

  static Future<Box<dynamic>> openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  /// The stored key, or null when the user has not set one.
  Future<OwnKey?> read() async {
    try {
      return OwnKey.fromMap(box?.get(_keyName));
    } catch (_) {
      return null;
    }
  }

  /// Saves a key. Throws only when the box is open and the write fails; a
  /// caller showing a "saved" message must await this, because telling someone
  /// their key is stored when it is not is the worst possible bug here.
  Future<void> save(OwnKey key) async {
    final target = box;
    if (target == null) {
      throw StateError('The key store is not available on this install.');
    }
    await target.put(_keyName, key.toMap());
  }

  /// Deletes the key from the device.
  Future<void> clear() async {
    try {
      await box?.delete(_keyName);
    } catch (_) {
      // Nothing stored, nothing to delete.
    }
  }

  /// True when a key is present — for the settings row's state, without
  /// loading the secret into a widget.
  bool get hasKey {
    try {
      return OwnKey.fromMap(box?.get(_keyName)) != null;
    } catch (_) {
      return false;
    }
  }
}
