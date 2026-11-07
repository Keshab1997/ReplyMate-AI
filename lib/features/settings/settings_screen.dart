import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/reply_options.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../shared/widgets/choice_chips.dart';
import '../admin/admin_gate_screen.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../../shared/widgets/section_label.dart';
import '../app_selection/app_selection_screen.dart';
import '../notifications/providers/notification_providers.dart';
import '../overlay/providers/bubble_providers.dart';
import '../permissions/permission_setup_screen.dart';
import '../permissions/providers/permission_provider.dart';
import 'providers/preferences_provider.dart';

/// Screen 8 plus the privacy screen (9): defaults, permission state, and the
/// privacy explanation with a working "clear local preferences" control.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear local preferences?'),
        content: const Text(
          'Language, tone, length, selected apps and onboarding state are '
          'removed from this device. Any in-memory notification context and '
          'pending quick-reply action are cleared too; message history is not '
          'stored.',
        ),
        actions: [
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

  /// Turns the floating reply bubble on or off (default off).
  ///
  /// Enabling asks for the Android 13+ notification permission first, because
  /// without it the bubble's own notification and the fallback notification
  /// cannot appear - and the user deserves to know that before wondering why
  /// nothing showed up. A refusal is reported, never hidden, and never undoes
  /// the choice.
  Future<void> _setBubble(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    if (enabled) {
      final notificationsAllowed = await ref
          .read(notificationsBridgeProvider)
          .requestNotificationPermission();
      if (!notificationsAllowed && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are not allowed, so the bubble notification and '
              'the fallback notification cannot appear. The bubble still works '
              'while ReplyMate is running.',
            ),
          ),
        );
      }
    }
    await ref.read(bubbleEnabledProvider.notifier).setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final permissionEnabled = ref.watch(listenerPermissionProvider);
    final overlayEnabled = ref.watch(overlayProvider);
    final bubbleEnabled = ref.watch(bubbleEnabledProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          children: [
            PermissionStatusCard(
              enabled: permissionEnabled,
              onManage: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PermissionSetupScreen(),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Reply bubble'),
            Card(
              child: SwitchListTile(
                value: bubbleEnabled,
                // Off - and unswitchable - until Android actually lets us draw
                // over other apps. A switch that promises something the OS
                // refuses would be the dishonest version of this control.
                onChanged: overlayEnabled
                    ? (value) => _setBubble(context, ref, value)
                    : null,
                title: const Text('Floating reply bubble'),
                subtitle: Text(
                  overlayEnabled
                      ? 'Shows a bubble over the app you are in when an '
                            'allowed app sends a message. Off by default; turn '
                            'it off again any time.'
                      : 'Needs the optional "Display over other apps" access. '
                            'Grant it on the notification access screen; '
                            'without it, nothing changes.',
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Default language'),
            ChoiceChips<ReplyLanguage>(
              options: ReplyLanguage.values,
              selected: preferences.language,
              labelOf: (language) => language.label,
              onSelected: (language) =>
                  ref.read(preferencesProvider.notifier).setLanguage(language),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Default tone'),
            ChoiceChips<ReplyTone>(
              options: ReplyTone.values,
              selected: preferences.tone,
              labelOf: (tone) => tone.label,
              onSelected: (tone) =>
                  ref.read(preferencesProvider.notifier).setTone(tone),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Default length'),
            ChoiceChips<ReplyLength>(
              options: ReplyLength.values,
              selected: preferences.length,
              labelOf: (length) => length.label,
              onSelected: (length) =>
                  ref.read(preferencesProvider.notifier).setLength(length),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppSelectionScreen(),
                ),
              ),
              child: const Text('Supported apps'),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            if (ref.watch(firebaseReadyProvider))
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminGateScreen(),
                  ),
                ),
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Admin'),
              ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Privacy'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notification access lets ReplyMate see notifications '
                      'from the apps you selected - never inside the apps. '
                      'When you generate suggestions, the message text you '
                      'provide is sent to an AI service to draft replies. '
                      'Conversations are not stored, and message content is '
                      'never logged.',
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    OutlinedButton(
                      onPressed: () => _confirmClear(context, ref),
                      child: const Text('Clear local preferences'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
