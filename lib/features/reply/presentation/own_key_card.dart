import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../data/own_key_reply_repository.dart';
import '../data/own_key_store.dart';
import '../providers/own_key_provider.dart';

/// Settings → "Your own AI key".
///
/// The point of the card is a promise it can keep: the key stays on this phone.
/// So it says that, in the card, where the user is typing — not in a README.
/// The field is obscured, prefilled with nothing, and the saved key is never
/// rendered back: "set" is enough state to show.
class OwnKeyCard extends ConsumerStatefulWidget {
  const OwnKeyCard({super.key});

  @override
  ConsumerState<OwnKeyCard> createState() => _OwnKeyCardState();
}

class _OwnKeyCardState extends ConsumerState<OwnKeyCard> {
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  OwnKeyProvider _provider = OwnKeyProvider.all.first;
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _applyDefaults(OwnKeyProvider provider) {
    setState(() {
      _provider = provider;
      if (provider.id != 'custom') {
        _baseUrlController.text = provider.baseUrl;
        _modelController.text = provider.model;
      }
    });
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your key first.');
      return;
    }
    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() => _error = 'Base URL and model are required.');
      return;
    }
    if (!baseUrl.startsWith('https://')) {
      setState(() => _error = 'Base URL must start with https://');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ownKeyStoreProvider)
          .save(
            OwnKey(
              key: key,
              provider: _provider.id,
              baseUrl: baseUrl,
              model: model,
            ),
          );
      ref.invalidate(ownKeyPresentProvider);
      if (!mounted) return;
      // The controller is cleared only after the write succeeded: a "Saved"
      // message over a key that was not stored is the worst bug this card
      // could have.
      _keyController.clear();
      setState(() {
        _busy = false;
        _editing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Key saved on this device')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save the key on this device.';
      });
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove your key?'),
        content: const Text(
          'The key is deleted from this phone and AI replies stop until you '
          'add one again. Offline suggestions keep working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ownKeyStoreProvider).clear();
    ref.invalidate(ownKeyPresentProvider);
    if (!mounted) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Key removed from this device')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasKey = ref.watch(ownKeyPresentProvider).value ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasKey ? Icons.vpn_key : Icons.vpn_key_outlined,
                  size: 20,
                  color: hasKey
                      ? AppTheme.mint
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasKey ? 'Your key is set' : 'Use your own AI key',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The key is stored on this phone only — never in Firestore, '
              'never in a backup. It is sent to the provider you choose and '
              'nowhere else.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (hasKey && !_editing) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _editing = true;
                      _applyDefaults(OwnKeyProvider.all.first);
                    }),
                    child: const Text('Replace'),
                  ),
                  TextButton(onPressed: _remove, child: const Text('Remove')),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _provider.id,
                decoration: const InputDecoration(
                  labelText: 'Provider',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final provider in OwnKeyProvider.all)
                    DropdownMenuItem(
                      value: provider.id,
                      child: Text(provider.label),
                    ),
                ],
                onChanged: (value) {
                  final provider = OwnKeyProvider.byId(value ?? '');
                  if (provider != null) _applyDefaults(provider);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  hintText: 'sk-…',
                  helperText:
                      'Hidden while typing. It never leaves this phone.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Wrap, not Row: in a constrained card the buttons must be able
              // to stack rather than force an infinite width on a narrow
              // screen or a large text scale.
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasKey)
                      TextButton(
                        onPressed: () => setState(() {
                          _editing = false;
                          _error = null;
                        }),
                        child: const Text('Cancel'),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Save key'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The store, opened lazily. A box that cannot open leaves the feature off
/// rather than crashing Settings.
final Provider<OwnKeyStore> ownKeyStoreProvider = Provider<OwnKeyStore>((ref) {
  if (Hive.isBoxOpen(OwnKeyStore.boxName)) {
    return OwnKeyStore(box: Hive.box<dynamic>(OwnKeyStore.boxName));
  }
  return OwnKeyStore();
});
