import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/platform/notifications_bridge.dart';
import '../../shared/widgets/screen_header.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: candidates.when(
            data: (apps) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spaceMd,
                  AppTheme.spaceSm,
                  AppTheme.spaceMd,
                  AppTheme.spaceXl,
                ),
                children: [
                  ScreenHeader(
                    title: 'Supported apps',
                    subtitle: apps.isEmpty
                        ? 'Nothing to choose yet'
                        : '${selected.length} of ${apps.length} selected',
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  if (apps.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No supported messaging app is installed on '
                              'this device.',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You can still use ReplyMate by pasting or '
                              'selecting text.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                height: 1.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'APPS REPLYMATE MAY READ NOTIFICATIONS FROM',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    Card(
                      child: Column(
                        children: [
                          for (var index = 0; index < apps.length; index++) ...[
                            if (index > 0) const Divider(height: 1),
                            CheckboxListTile(
                              value: selected.contains(apps[index].packageName),
                              onChanged: (_) => ref
                                  .read(selectedAppsProvider.notifier)
                                  .toggle(apps[index].packageName),
                              title: Text(
                                apps[index].label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                'Notifications only - never inside the app',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.trailing,
                              activeColor: AppTheme.brandBright,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: isDark ? AppTheme.brandBright : AppTheme.brand,
                        ),
                        const SizedBox(width: AppTheme.spaceSm),
                        Expanded(
                          child: Text(
                            'An app appears here only after it has been seen '
                            'installed on this device. Support is claimed only '
                            'for what has been tested '
                            '(docs/SCREEN_SPECIFICATIONS.md, screen 5).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
                              height: 1.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Column(
                children: [
                  const ScreenHeader(title: 'Supported apps'),
                  const SizedBox(height: AppTheme.spaceLg),
                  Text(
                    'Could not read the installed app list.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
