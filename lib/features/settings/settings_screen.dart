import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/reply_options.dart';
import '../../shared/widgets/choice_chips.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../../shared/widgets/section_label.dart';
import '../app_selection/app_selection_screen.dart';
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
          'removed from this device. Nothing else is stored, so nothing '
          'else can be removed.',
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final permissionEnabled = ref.watch(listenerPermissionProvider);
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
