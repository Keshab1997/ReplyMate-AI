import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// One generated reply: editable text, copy/share actions, and conditional
/// quick reply. The quick-reply button is hidden - not just disabled - when
/// the source notification exposed no valid action, so the UI never promises a
/// capability Android did not offer.
class SuggestionCard extends StatefulWidget {
  const SuggestionCard({
    required this.controller,
    required this.quickReplyAvailable,
    required this.onCopy,
    required this.onShare,
    required this.onQuickReply,
    this.best = false,
    super.key,
  });

  final TextEditingController controller;
  final bool quickReplyAvailable;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onQuickReply;

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
                      color: AppTheme.brand.withValues(alpha: 0.22),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
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
              Row(
                children: [
                  _Action(
                    icon: Icons.copy_all_outlined,
                    label: 'Copy',
                    onPressed: () => widget.onCopy(widget.controller.text),
                  ),
                  _Action(
                    icon: _editing ? Icons.check : Icons.edit_outlined,
                    label: _editing ? 'Done' : 'Edit',
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
                  _Action(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onPressed: () => widget.onShare(widget.controller.text),
                  ),
                  const Spacer(),
                  if (widget.quickReplyAvailable)
                    FilledButton.icon(
                      onPressed: () =>
                          widget.onQuickReply(widget.controller.text),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Quick reply'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        backgroundColor: AppTheme.mint,
                        foregroundColor: const Color(0xFF062B1E),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'BEST FIT',
                style: TextStyle(
                  fontSize: 9,
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
      icon: Icon(icon, size: 15, color: colour),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: colour,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}
