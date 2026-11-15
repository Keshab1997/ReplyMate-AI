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

/// The icon for each option, not for each group.
///
/// The first version gave every chip in a group the same glyph - seven tones
/// with seven identical mood faces - which is a picture of a list, not a way to
/// read it. Each tone is a different register, so each one gets the glyph that
/// says which: a smile for friendly, a cup for casual, a briefcase for
/// professional. The two partner voices are hearts, filled and hollow, because
/// the domain treats them as a persona rather than a register (see
/// [ReplyTone.isRomantic]) and a filled heart against a hollow one is the
/// shortest honest way to say "these two are somebody, not a style".
IconData toneIcon(ReplyTone tone) => switch (tone) {
  ReplyTone.friendly => Icons.sentiment_satisfied_alt_rounded,
  ReplyTone.casual => Icons.local_cafe_rounded,
  ReplyTone.professional => Icons.work_outline_rounded,
  ReplyTone.polite => Icons.volunteer_activism_rounded,
  ReplyTone.funny => Icons.theater_comedy_rounded,
  ReplyTone.shortAndDirect => Icons.bolt_rounded,
  ReplyTone.premika => Icons.favorite_rounded,
  ReplyTone.premik => Icons.favorite_border_rounded,
};

/// Short is a short line, medium a paragraph, long a page: the glyph is the
/// length, so the row can be understood before it is read.
IconData lengthIcon(ReplyLength length) => switch (length) {
  ReplyLength.short => Icons.short_text_rounded,
  ReplyLength.medium => Icons.subject_rounded,
  ReplyLength.long => Icons.notes_rounded,
};

/// The number *is* the icon. `looks_one/two/three` reads instantly, and a row
/// of "1 2 3" chips with the same list glyph is exactly the ambiguity this
/// screen is trying to remove.
IconData countIcon(int count) => switch (count) {
  1 => Icons.looks_one_rounded,
  2 => Icons.looks_two_rounded,
  _ => Icons.looks_3_rounded,
};

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

        // One card, four labelled groups, rules between them. There is no
        // uppercase "REPLY STYLE" heading above it: the screen is already
        // called that, and a label that repeats the title is decoration, not
        // structure. (The screenshot said so before the code review did.)
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.spaceLg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Group(
                    icon: AppIcons.language,
                    label: strings.languageLabel,
                    // The current choice is spelled out beside the label: with
                    // ten chips on screen, "which one is live" should not
                    // require scanning for a tint.
                    current: preferences.language.label,
                    child: ChoiceChips<ReplyLanguage>(
                      options: ReplyLanguage.values,
                      selected: preferences.language,
                      labelOf: (language) => language.label,
                      iconOf: (_) => AppIcons.language,
                      onSelected: (language) => ref
                          .read(preferencesProvider.notifier)
                          .setLanguage(language),
                    ),
                  ),
                  const _GroupDivider(),
                  _Group(
                    icon: AppIcons.tone,
                    label: strings.toneLabel,
                    current: preferences.tone.label,
                    child: ChoiceChips<ReplyTone>(
                      options: ReplyTone.values,
                      selected: preferences.tone,
                      labelOf: (tone) => tone.label,
                      iconOf: toneIcon,
                      onSelected: (tone) =>
                          ref.read(preferencesProvider.notifier).setTone(tone),
                    ),
                  ),
                  const _GroupDivider(),
                  _Group(
                    icon: AppIcons.length,
                    label: strings.lengthLabel,
                    current: preferences.length.label,
                    child: ChoiceChips<ReplyLength>(
                      options: ReplyLength.values,
                      selected: preferences.length,
                      labelOf: (length) => length.label,
                      iconOf: lengthIcon,
                      onSelected: (length) => ref
                          .read(preferencesProvider.notifier)
                          .setLength(length),
                    ),
                  ),
                  const _GroupDivider(),
                  _Group(
                    icon: AppIcons.count,
                    label: strings.howManyOptions,
                    current: '${preferences.suggestionCount}',
                    child: ChoiceChips<int>(
                      options: List<int>.generate(
                        AppConstants.maxSuggestionCount -
                            AppConstants.minSuggestionCount +
                            1,
                        (index) => AppConstants.minSuggestionCount + index,
                      ),
                      selected: preferences.suggestionCount,
                      labelOf: (count) => '$count',
                      iconOf: countIcon,
                      onSelected: (count) => ref
                          .read(preferencesProvider.notifier)
                          .setSuggestionCount(count),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Every screen and the bubble use this style. '
                          'Nothing asks again.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            height: 1.45,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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

/// A labelled group inside the card: icon, name, the live value, then the chips.
class _Group extends StatelessWidget {
  const _Group({
    required this.icon,
    required this.label,
    required this.current,
    required this.child,
  });

  final IconData icon;
  final String label;
  final String current;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            // Never wider than a third: a long tone name must not push the
            // label off the row on a narrow phone.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                current,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// A hairline between groups: enough structure to separate, not enough to turn
/// the card back into four cards.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd - 2),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: 0.35),
      ),
    );
  }
}
