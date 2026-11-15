import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import 'app_theme.dart';

/// The stored appearance choices. Palette changes only the accent family;
/// brightness may follow the device, or be pinned independently.
class AppThemePreferences {
  const AppThemePreferences({
    this.palette = AppPalette.violet,
    this.mode = AppAppearanceMode.system,
  });

  final AppPalette palette;
  final AppAppearanceMode mode;

  AppThemePreferences copyWith({
    AppPalette? palette,
    AppAppearanceMode? mode,
  }) => AppThemePreferences(
    palette: palette ?? this.palette,
    mode: mode ?? this.mode,
  );
}

enum AppAppearanceMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppAppearanceMode(this.storageValue);
  final String storageValue;

  static AppAppearanceMode fromStorage(String? value) =>
      AppAppearanceMode.values.firstWhere(
        (mode) => mode.storageValue == value,
        orElse: () => AppAppearanceMode.system,
      );
}

final NotifierProvider<AppThemePreferencesNotifier, AppThemePreferences>
appThemePreferencesProvider =
    NotifierProvider<AppThemePreferencesNotifier, AppThemePreferences>(
      AppThemePreferencesNotifier.new,
    );

class AppThemePreferencesNotifier extends Notifier<AppThemePreferences> {
  bool _alive = true;

  @override
  AppThemePreferences build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return const AppThemePreferences();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_alive) return;
    state = AppThemePreferences(
      palette: AppPalette.fromStorage(
        prefs.getString(AppConstants.prefThemePalette),
      ),
      mode: AppAppearanceMode.fromStorage(
        prefs.getString(AppConstants.prefThemeMode),
      ),
    );
  }

  Future<void> setPalette(AppPalette palette) async {
    state = state.copyWith(palette: palette);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefThemePalette, palette.storageValue);
  }

  Future<void> setMode(AppAppearanceMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefThemeMode, mode.storageValue);
  }

  Future<void> reset() async {
    state = const AppThemePreferences();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefThemePalette);
    await prefs.remove(AppConstants.prefThemeMode);
  }
}
