import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// A wrapped row of single-select chips, generic over the option type so
/// language, tone and length selectors all render identically.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    super.key,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T option) labelOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.spaceSm,
      runSpacing: AppTheme.spaceSm,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(labelOf(option)),
            selected: option == selected,
            onSelected: (_) => onSelected(option),
          ),
      ],
    );
  }
}
