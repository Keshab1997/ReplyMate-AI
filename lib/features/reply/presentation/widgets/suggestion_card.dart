import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/app_strings.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_theme.dart';

/// One generated reply: editable text, and copy/share to hand it over.
/// There is no send button, and there never was one that worked. A reply is
/// handed to the messaging app only when the user pastes it, which is the one
/// route that works in every app on the allowlist.
class SuggestionCard extends StatefulWidget {
  const SuggestionCard({
    required this.controller,
    required this.onCopy,
    required this.onShare,
    this.best = false,
    this.strings = const EnglishStrings(),
    super.key,
  });

  /// The interface language. A default rather than a lookup so this card stays a
  /// plain widget: the screens that know the language pass it down.
  final AppStrings strings;

  final TextEditingController controller;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onShare;

  /// The first suggestion, marked so the user does not have to compare three
  /// paragraphs to pick one.
  final bool best;

  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            color: isDark
                ? Colors.white.withValues(alpha: 0.045)
                : Colors.white,
            border: Border.all(
              color: widget.best
                  ? AppTheme.brandBright.withValues(alpha: 0.55)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.09)
                        : theme.colorScheme.outlineVariant),
            ),
            boxShadow: widget.best
                ? [
                    BoxShadow(
                      color: AppTheme.brand.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editing)
                TextField(
                  controller: widget.controller,
                  minLines: 2,
                  maxLines: 6,
                  autofocus: true,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : const Color(0xFFF3F6FC),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                )
              else
                Text(
                  widget.controller.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    fontSize: 14,
                  ),
                ),
              const SizedBox(height: AppTheme.spaceSm),
              Wrap(
                spacing: AppTheme.spaceXs,
                runSpacing: AppTheme.spaceXs,
                children: [
                  _Action(
                    icon: AppIcons.copy,
                    label: 'Copy',
                    onPressed: () => widget.onCopy(widget.controller.text),
                  ),
                  _Action(
                    icon: _editing ? AppIcons.done : AppIcons.editOutlined,
                    label: _editing ? 'Done' : 'Edit',
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
                  _Action(
                    icon: AppIcons.share,
                    label: widget.strings.share,
                    onPressed: () => widget.onShare(widget.controller.text),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.best)
          Positioned(
            top: -8,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                widget.strings.bestFit,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFF062B1E),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A quiet action: icon plus label, no button chrome, so the reply text keeps
/// the visual weight on the card.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: colour),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: colour,
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.38,
        ),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
