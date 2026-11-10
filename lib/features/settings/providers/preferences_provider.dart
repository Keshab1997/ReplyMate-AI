import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../app_selection/providers/selected_apps_provider.dart';
import '../../notifications/providers/notification_providers.dart';

/// The user's default reply preferences (FR-07 plus tone/length defaults).
/// Interface language and AI output language are independent settings in the
/// docs; the MVP ships only the output-language default.
class ReplyPreferences {
  const ReplyPreferences({
    this.language = ReplyLanguage.english,
    this.tone = ReplyTone.friendly,
    this.length = ReplyLength.short,
    this.suggestionCount = AppConstants.defaultSuggestionCount,
  });

  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;

  /// How many replies to draft per request. Held here, not in the panel, so
  /// the bubble and the composer agree without asking twice.
  final int suggestionCount;

  ReplyPreferences copyWith({
    ReplyLanguage? language,
    ReplyTone? tone,
    ReplyLength? length,
    int? suggestionCount,
  }) => ReplyPreferences(
    language: language ?? this.language,
    tone: tone ?? this.tone,
    length: length ?? this.length,
    suggestionCount: suggestionCount ?? this.suggestionCount,
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
      suggestionCount: _clampCount(
        prefs.getInt(AppConstants.prefSuggestionCount),
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

  Future<void> setSuggestionCount(int count) => _update(
    state.copyWith(suggestionCount: _clampCount(count)),
    (prefs) => prefs.setInt(AppConstants.prefSuggestionCount, count),
  );

  /// A stored count outside the supported range would fail validation on every
  /// request, so it is clamped on the way in rather than reported later.
  static int _clampCount(int? value) {
    if (value == null) return AppConstants.defaultSuggestionCount;
    if (value < AppConstants.minSuggestionCount) {
      return AppConstants.minSuggestionCount;
    }
    if (value > AppConstants.maxSuggestionCount) {
      return AppConstants.maxSuggestionCount;
    }
    return value;
  }

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
    await prefs.remove(AppConstants.prefSuggestionCount);
    await prefs.remove(AppConstants.prefSelectedApps);
    await prefs.remove(AppConstants.prefOnboardingDone);
    state = const ReplyPreferences();
    ref.read(capturedNotificationsProvider.notifier).clear();
    await ref.read(notificationsBridgeProvider).clearRetainedContext();
    final selectedApps = ref.read(selectedAppsProvider.notifier);
    await selectedApps.ready;
    await selectedApps.clear();
  }
}
