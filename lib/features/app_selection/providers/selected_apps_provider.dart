import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../notifications/providers/notification_providers.dart';

/// The user's messaging-app allowlist (FR-03).
///
/// The selection is the privacy boundary: the native listener processes only
/// these packages. Every change is mirrored down to the native layer
/// immediately, so a revoke takes effect without a restart.
final StateNotifierProvider<SelectedAppsNotifier, List<String>>
selectedAppsProvider =
    StateNotifierProvider<SelectedAppsNotifier, List<String>>(
      (Ref ref) => SelectedAppsNotifier(ref),
    );

class SelectedAppsNotifier extends StateNotifier<List<String>> {
  SelectedAppsNotifier(this._ref) : super(const <String>[]) {
    ready = _load();
  }

  final Ref _ref;

  /// Completes when the stored selection has been read and re-asserted
  /// natively. Tests await it instead of racing the load.
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(AppConstants.prefSelectedApps);
    if (stored != null && mounted) {
      state = stored;
      // Re-assert the allowlist natively: the native prefs survive, but the
      // two must never disagree after a reinstall or a data clear.
      await _ref.read(notificationsBridgeProvider).setAllowedPackages(stored);
    }
  }

  bool isSelected(String packageName) => state.contains(packageName);

  Future<void> toggle(String packageName) async {
    final next = <String>[...state];
    if (!next.remove(packageName)) next.add(packageName);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(AppConstants.prefSelectedApps, next);
    await _ref.read(notificationsBridgeProvider).setAllowedPackages(next);
  }

  Future<void> clear() async {
    state = const <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefSelectedApps);
    await _ref.read(notificationsBridgeProvider).setAllowedPackages(const []);
  }
}
