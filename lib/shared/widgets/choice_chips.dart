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
    this.iconOf,
    super.key,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T option) labelOf;
  final IconData Function(T option)? iconOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.spaceSm,
      runSpacing: AppTheme.spaceSm,
      children: [
        for (final option in options)
          ChoiceChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar: iconOf == null ? null : Icon(iconOf!(option), size: 16),
            showCheckmark: iconOf == null,
            label: Text(labelOf(option)),
            selected: option == selected,
            onSelected: (_) => onSelected(option),
          ),
      ],
    );
  }
}
