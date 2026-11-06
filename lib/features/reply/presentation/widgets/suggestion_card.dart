import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// One generated reply: editable text, copy/share actions, and conditional
/// quick reply. The quick-reply button is hidden - not just disabled - when
/// the source notification exposed no valid action, so the UI never promises
/// a capability Android did not offer.
class SuggestionCard extends StatefulWidget {
  const SuggestionCard({
    required this.controller,
    required this.quickReplyAvailable,
    required this.onCopy,
    required this.onShare,
    required this.onQuickReply,
    super.key,
  });

  final TextEditingController controller;
  final bool quickReplyAvailable;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onQuickReply;

  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_editing)
              TextField(
                controller: widget.controller,
                minLines: 2,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              )
            else
              Text(
                widget.controller.text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            const SizedBox(height: AppTheme.spaceSm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => widget.onCopy(widget.controller.text),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Copy'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _editing = !_editing),
                  icon: Icon(
                    _editing ? Icons.check : Icons.edit_outlined,
                    size: 18,
                  ),
                  label: Text(_editing ? 'Done' : 'Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: () => widget.onShare(widget.controller.text),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
                if (widget.quickReplyAvailable)
                  FilledButton.icon(
                    onPressed: () =>
                        widget.onQuickReply(widget.controller.text),
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Quick reply'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
