import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/platform/notifications_bridge.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../../shared/widgets/section_label.dart';
import '../app_selection/app_selection_screen.dart';
import '../app_selection/providers/selected_apps_provider.dart';
import '../permissions/permission_setup_screen.dart';
import '../permissions/providers/permission_provider.dart';
import '../reply/presentation/reply_composer_screen.dart';
import '../settings/providers/preferences_provider.dart';
import '../settings/settings_screen.dart';

/// Screen 3 of docs/SCREEN_SPECIFICATIONS.md: permission status, selected
/// apps, language and tone defaults, and the entry point into the composer.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionEnabled = ref.watch(listenerPermissionProvider);
    final selectedApps = ref.watch(selectedAppsProvider);
    final preferences = ref.watch(preferencesProvider);
    final candidates =
        ref.watch(candidateAppsProvider).value ?? const <CandidateApp>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReplyMate AI'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
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
            SectionLabel('Selected apps'),
            if (selectedApps.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  child: Row(
                    children: [
                      const Expanded(child: Text('No apps selected yet.')),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AppSelectionScreen(),
                          ),
                        ),
                        child: const Text('Choose'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                children: [
                  for (final packageName in selectedApps)
                    ActionChip(
                      avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(labelForPackage(candidates, packageName)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppSelectionScreen(),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppTheme.spaceLg),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    icon: Icons.translate_rounded,
                    caption: 'Language',
                    value: preferences.language.label,
                  ),
                ),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: _SummaryCard(
                    icon: Icons.mood_outlined,
                    caption: 'Default tone',
                    value: preferences.tone.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceLg),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReplyComposerScreen(),
                ),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate a reply'),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppSelectionScreen(),
                ),
              ),
              child: const Text('Manage supported apps'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.caption,
    required this.value,
  });

  final IconData icon;
  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: AppTheme.spaceSm),
            Text(caption, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
