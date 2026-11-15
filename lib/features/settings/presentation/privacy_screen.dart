import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../settings/providers/preferences_provider.dart';
import 'settings_sub_screen.dart';

/// Settings → Privacy. The promises, the explanation, and the one button that
/// removes everything this phone kept.
///
/// It used to sit under four cards in a single scrolling screen, which is the
/// wrong place for the part of Settings a person opens when they are worried.
/// Now it has a name in the hub and a screen of its own.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear local preferences?'),
        content: const Text(
          'Language, tone, per-chat reply styles, selected apps, saved reply '
          'templates and onboarding state are removed from this device. Any '
          'in-memory notification context and pending quick-reply action are '
          'cleared too; message history is not stored.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(preferencesProvider.notifier).clearAll();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);

    return SettingsSubScreen(
      title: strings.privacySection,
      subtitle: strings.settingsPrivacyHint,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.spaceSm),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Promise(
                    icon: Icons.delete_outline_rounded,
                    title: strings.messagesNeverStored,
                    body: strings.messagesNeverStoredBody,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  _Promise(
                    icon: Icons.pan_tool_alt_outlined,
                    title: strings.nothingSentAlone,
                    body: strings.nothingSentAloneBody,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(
                    'Notification access lets ReplyMate see notifications '
                    'from the apps you selected - never inside the apps. '
                    'When you generate suggestions, the message text you '
                    'provide is sent to an AI service to draft replies. '
                    'Conversations are not stored, and message content '
                    'is never logged.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      height: 1.55,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  OutlinedButton(
                    onPressed: () => _confirmClear(context, ref),
                    child: Text(strings.clearLocalPreferences),
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

/// One privacy promise: icon, claim, one sentence of proof.
class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSurfaces.iconBadge(
          context,
          icon: icon,
          color: theme.brightness == Brightness.dark
              ? AppTheme.mint
              : const Color(0xFF087F5B),
          size: 34,
        ),
        const SizedBox(width: AppTheme.spaceSm + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
