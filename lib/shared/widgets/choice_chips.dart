import 'package:material_ui/material_ui.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppTheme.spaceSm,
      runSpacing: AppTheme.spaceSm,
      children: [
        for (final option in options)
          Builder(
            builder: (context) {
              final isSelected = option == selected;
              return ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.padded,
                // A chip with an icon loses its checkmark, so the icon carries
                // the selection instead: brand colour when chosen, muted when
                // not. Without this, ten identical grey glyphs and one tinted
                // pill is the only thing saying which tone is live.
                avatar: iconOf == null
                    ? null
                    : Icon(
                        iconOf!(option),
                        size: 16,
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                showCheckmark: iconOf == null,
                label: Text(labelOf(option)),
                selected: isSelected,
                onSelected: (_) => onSelected(option),
              );
            },
          ),
      ],
    );
  }
}
