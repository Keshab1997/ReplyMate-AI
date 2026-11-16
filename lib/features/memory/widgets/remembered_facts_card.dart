import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../data/remembered_facts_store.dart';

/// The list of things the user told the app to remember.
///
/// Deliberately a list of text the user wrote, with a delete on every row and
/// an "add" field - never a summary, never a profile. The whole value of this
/// feature over an inferred one is that every line here can be read back,
/// corrected and removed by the person it is about.
class RememberedFactsCard extends ConsumerStatefulWidget {
  const RememberedFactsCard({super.key});

  @override
  ConsumerState<RememberedFactsCard> createState() =>
      _RememberedFactsCardState();
}

class _RememberedFactsCardState extends ConsumerState<RememberedFactsCard> {
  final TextEditingController _controller = TextEditingController();
  List<RememberedFact> _facts = const <RememberedFact>[];
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facts = await ref.read(rememberedFactsStoreProvider).all();
    if (!mounted) return;
    setState(() {
      _facts = facts;
      _loaded = true;
    });
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final facts = await ref.read(rememberedFactsStoreProvider).add(text);
    if (!mounted) return;
    setState(() {
      _facts = facts;
      _busy = false;
    });
    _controller.clear();
  }

  Future<void> _remove(RememberedFact fact) async {
    final facts = await ref.read(rememberedFactsStoreProvider).remove(fact.id);
    if (!mounted) return;
    setState(() => _facts = facts);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(appStringsProvider);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.rememberedFactsHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('rememberedFactField'),
                controller: _controller,
                maxLength: RememberedFactsStore.maxFactLength,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: strings.rememberedFactHint,
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spaceXs),
            IconButton.filled(
              key: const Key('addRememberedFact'),
              tooltip: strings.rememberedFactAdd,
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
        if (_loaded && _facts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spaceSm),
            child: Text(
              strings.rememberedFactsEmpty,
              key: const Key('rememberedFactsEmpty'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final fact in _facts)
          ListTile(
            key: ValueKey<String>('rememberedFact-${fact.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              Icons.push_pin_outlined,
              size: 18,
              color: scheme.primary,
            ),
            title: Text(fact.text),
            trailing: IconButton(
              key: ValueKey<String>('deleteRememberedFact-${fact.id}'),
              tooltip: strings.rememberedFactDelete,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => _remove(fact),
            ),
          ),
      ],
    );
  }
}
