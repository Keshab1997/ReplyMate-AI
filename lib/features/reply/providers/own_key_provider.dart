import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/own_key_card.dart' show ownKeyStoreProvider;

/// Whether a personal key is present, for the settings row's state.
///
/// Deliberately a boolean and not the key: no widget should ever hold the
/// secret, so nothing can render it, log it, or carry it into an error report.
final FutureProvider<bool> ownKeyPresentProvider = FutureProvider<bool>((
  ref,
) async {
  final store = ref.watch(ownKeyStoreProvider);
  return (await store.read()) != null;
});
