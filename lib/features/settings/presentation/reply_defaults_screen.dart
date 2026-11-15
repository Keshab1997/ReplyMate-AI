import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/choice_chips.dart';
import '../../settings/providers/preferences_provider.dart';
import 'settings_sub_screen.dart';

/// Settings → Reply defaults. The interface language and the four things every
/// draft is built from.
///
/// This is the section the composer deliberately does *not* ask any more: one
/// screen owns these answers, and every other surface reads them.
class ReplyDefaultsScreen extends ConsumerWidget {
  const ReplyDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final appLanguage = ref.watch(appLanguageProvider);
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);

    return SettingsSubScreen(
      title: strings.replyStyle,
      subtitle: strings.settingsReplyHint,
      children: <Widget>[
        SettingsSection(
          topSpace: AppTheme.spaceSm,
          label: strings.appLanguageSection,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: AppTheme.spaceSm,
                    runSpacing: AppTheme.spaceSm,
                    children: <Widget>[
                      for (final language in AppLanguage.values)
                        ChoiceChip(
                          label: Text(language.label),
                          selected: language == appLanguage,
                          onSelected: (_) => ref
                              .read(appLanguageProvider.notifier)
                              .setLanguage(language),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    strings.appLanguageNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SettingsSection(
          label: strings.replyStyle,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.languageLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ChoiceChips<ReplyLanguage>(
                    options: ReplyLanguage.values,
                    selected: preferences.language,
                    labelOf: (language) => language.label,
                    iconOf: (_) => AppIcons.language,
                    onSelected: (language) => ref
                        .read(preferencesProvider.notifier)
                        .setLanguage(language),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(
                    strings.toneLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ChoiceChips<ReplyTone>(
                    options: ReplyTone.values,
                    selected: preferences.tone,
                    labelOf: (tone) => tone.label,
                    iconOf: (_) => AppIcons.tone,
                    onSelected: (tone) =>
                        ref.read(preferencesProvider.notifier).setTone(tone),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(
                    strings.lengthLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ChoiceChips<ReplyLength>(
                    options: ReplyLength.values,
                    selected: preferences.length,
                    labelOf: (length) => length.label,
                    iconOf: (_) => AppIcons.length,
                    onSelected: (length) => ref
                        .read(preferencesProvider.notifier)
                        .setLength(length),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(
                    strings.howManyOptions,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ChoiceChips<int>(
                    options: List<int>.generate(
                      AppConstants.maxSuggestionCount -
                          AppConstants.minSuggestionCount +
                          1,
                      (index) => AppConstants.minSuggestionCount + index,
                    ),
                    selected: preferences.suggestionCount,
                    labelOf: (count) => '$count',
                    iconOf: (_) => AppIcons.count,
                    onSelected: (count) => ref
                        .read(preferencesProvider.notifier)
                        .setSuggestionCount(count),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    'Every screen and the bubble use this style. '
                    'Nothing asks again.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
