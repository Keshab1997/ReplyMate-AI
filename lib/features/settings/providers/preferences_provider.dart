import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../app_selection/providers/selected_apps_provider.dart';

/// The user's default reply preferences (FR-07 plus tone/length defaults).
/// Interface language and AI output language are independent settings in the
/// docs; the MVP ships only the output-language default.
class ReplyPreferences {
  const ReplyPreferences({
    this.language = ReplyLanguage.english,
    this.tone = ReplyTone.friendly,
    this.length = ReplyLength.short,
  });

  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;

  ReplyPreferences copyWith({
    ReplyLanguage? language,
    ReplyTone? tone,
    ReplyLength? length,
  }) => ReplyPreferences(
    language: language ?? this.language,
    tone: tone ?? this.tone,
    length: length ?? this.length,
  );
}

final NotifierProvider<PreferencesNotifier, ReplyPreferences>
preferencesProvider = NotifierProvider<PreferencesNotifier, ReplyPreferences>(
  PreferencesNotifier.new,
);

class PreferencesNotifier extends Notifier<ReplyPreferences> {
  bool _alive = true;

  @override
  ReplyPreferences build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return const ReplyPreferences();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_alive) return;
    state = ReplyPreferences(
      language: ReplyLanguage.fromCode(
        prefs.getString(AppConstants.prefDefaultLanguage),
      ),
      tone: ReplyTone.fromName(prefs.getString(AppConstants.prefDefaultTone)),
      length: ReplyLength.fromName(
        prefs.getString(AppConstants.prefDefaultLength),
      ),
    );
  }

  Future<void> setLanguage(ReplyLanguage language) => _update(
    state.copyWith(language: language),
    (prefs) => prefs.setString(AppConstants.prefDefaultLanguage, language.code),
  );

  Future<void> setTone(ReplyTone tone) => _update(
    state.copyWith(tone: tone),
    (prefs) => prefs.setString(AppConstants.prefDefaultTone, tone.name),
  );

  Future<void> setLength(ReplyLength length) => _update(
    state.copyWith(length: length),
    (prefs) => prefs.setString(AppConstants.prefDefaultLength, length.name),
  );

  Future<void> _update(
    ReplyPreferences next,
    Future<void> Function(SharedPreferences prefs) persist,
  ) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await persist(prefs);
  }

  /// "Clear local preferences" from the privacy screen: everything the app
  /// stored locally goes away, including the app allowlist.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefDefaultLanguage);
    await prefs.remove(AppConstants.prefDefaultTone);
    await prefs.remove(AppConstants.prefDefaultLength);
    await prefs.remove(AppConstants.prefSelectedApps);
    await prefs.remove(AppConstants.prefOnboardingDone);
    state = const ReplyPreferences();
    await ref.read(selectedAppsProvider.notifier).clear();
  }
}
