import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/choice_chips.dart';

/// The one place the reply style is changed from the Reply tab.
///
/// It exists because the composer used to carry all four chip rows inline: on a
/// 390×844 screen that is ~330 dp of chips between the message and the button,
/// so the screen stopped looking like a place to write and started looking like
/// a settings form with a text box in it. The style is a decision, not a
/// transcript - it belongs one tap away, with the current choice always visible
/// in the header.
class ReplyStyleSheet {
  ReplyStyleSheet._();

  /// Returns the chosen style, or null when the sheet was dismissed without a
  /// choice - so a caller can tell "unchanged" from "chose the same values".
  static Future<ReplyStyleChoice?> show(
    BuildContext context, {
    required AppStrings strings,
    required ReplyLanguage language,
    required ReplyTone tone,
    required ReplyLength length,
    required int count,
  }) {
    return showModalBottomSheet<ReplyStyleChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ReplyStyleSheetBody(
        strings: strings,
        language: language,
        tone: tone,
        length: length,
        count: count,
      ),
    );
  }
}

/// The four axes every request carries (FR-06, FR-07).
class ReplyStyleChoice {
  const ReplyStyleChoice({
    required this.language,
    required this.tone,
    required this.length,
    required this.count,
  });

  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;
  final int count;
}

class _ReplyStyleSheetBody extends StatefulWidget {
  const _ReplyStyleSheetBody({
    required this.strings,
    required this.language,
    required this.tone,
    required this.length,
    required this.count,
  });

  final AppStrings strings;
  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;
  final int count;

  @override
  State<_ReplyStyleSheetBody> createState() => _ReplyStyleSheetBodyState();
}

class _ReplyStyleSheetBodyState extends State<_ReplyStyleSheetBody> {
  late ReplyLanguage _language = widget.language;
  late ReplyTone _tone = widget.tone;
  late ReplyLength _length = widget.length;
  late int _count = widget.count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.strings;
    final label = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget section(String text, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: label),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spaceMd,
          0,
          AppTheme.spaceMd,
          AppTheme.spaceMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.replyStyleTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              strings.oneWayToSayIt,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            section(
              strings.languageLabel,
              ChoiceChips<ReplyLanguage>(
                options: ReplyLanguage.values,
                selected: _language,
                labelOf: (language) => language.label,
                iconOf: (_) => AppIcons.language,
                onSelected: (language) => setState(() => _language = language),
              ),
            ),
            section(
              strings.toneLabel,
              ChoiceChips<ReplyTone>(
                options: ReplyTone.values,
                selected: _tone,
                labelOf: (tone) => tone.label,
                iconOf: (_) => AppIcons.tone,
                onSelected: (tone) => setState(() => _tone = tone),
              ),
            ),
            section(
              strings.lengthLabel,
              ChoiceChips<ReplyLength>(
                options: ReplyLength.values,
                selected: _length,
                labelOf: (length) => length.label,
                iconOf: (_) => AppIcons.length,
                onSelected: (length) => setState(() => _length = length),
              ),
            ),
            section(
              strings.howManyOptions,
              ChoiceChips<int>(
                options: List<int>.generate(
                  AppConstants.maxSuggestionCount -
                      AppConstants.minSuggestionCount +
                      1,
                  (index) => AppConstants.minSuggestionCount + index,
                ),
                selected: _count,
                labelOf: (count) => '$count',
                iconOf: (_) => AppIcons.count,
                onSelected: (count) => setState(() => _count = count),
              ),
            ),
            AppSurfaces.primaryAction(
              context,
              label: strings.done,
              onPressed: () => Navigator.of(context).pop(
                ReplyStyleChoice(
                  language: _language,
                  tone: _tone,
                  length: _length,
                  count: _count,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
