import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/platform/notifications_bridge.dart';
import '../../shared/widgets/section_label.dart';
import '../notifications/providers/notification_providers.dart';
import 'providers/selected_apps_provider.dart';

/// Installed messaging apps ReplyMate can offer (native layer filters to
/// installed packages only, so this list never over-promises).
final FutureProvider<List<CandidateApp>> candidateAppsProvider =
    FutureProvider<List<CandidateApp>>(
      (Ref ref) => ref.watch(notificationsBridgeProvider).candidateApps(),
    );

/// Label for a package, falling back to the package name when the candidate
/// list is unavailable (tests, web preview).
String labelForPackage(List<CandidateApp> candidates, String packageName) =>
    candidates
        .firstWhere(
          (app) => app.packageName == packageName,
          orElse: () =>
              CandidateApp(packageName: packageName, label: packageName),
        )
        .label;

/// FR-03: choose which messaging apps ReplyMate may process. The selection is
/// the privacy boundary and is pushed to the native listener immediately.
class AppSelectionScreen extends ConsumerWidget {
  const AppSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(candidateAppsProvider);
    final selected = ref.watch(selectedAppsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Supported apps')),
      body: SafeArea(
        child: candidates.when(
          data: (apps) {
            if (apps.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppTheme.spaceLg),
                child: Text(
                  'No supported messaging app is installed on this device. '
                  'You can still use ReplyMate by pasting or selecting text.',
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              children: [
                const SectionLabel(
                  'Apps ReplyMate may read notifications from',
                ),
                Card(
                  child: Column(
                    children: [
                      for (final app in apps)
                        CheckboxListTile(
                          title: Text(app.label),
                          subtitle: const Text(
                            'Notifications only - never inside the app',
                          ),
                          value: selected.contains(app.packageName),
                          onChanged: (_) => ref
                              .read(selectedAppsProvider.notifier)
                              .toggle(app.packageName),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                Text(
                  'An app appears here only after it has been seen installed '
                  'on this device. Support is claimed only for what has been '
                  'tested (docs/SCREEN_SPECIFICATIONS.md, screen 5).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Padding(
            padding: EdgeInsets.all(AppTheme.spaceLg),
            child: Text('Could not read the installed app list.'),
          ),
        ),
      ),
    );
  }
}
