import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/platform/notifications_bridge.dart';
import '../../shared/widgets/app_icon.dart';
import '../../shared/widgets/screen_header.dart';
import '../notifications/providers/notification_providers.dart';
import 'providers/selected_apps_provider.dart';
import '../../core/l10n/app_strings.dart';

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

/// The candidate for a package, or null when the list is unavailable (tests,
/// web preview). Home uses this to draw the same icon the list draws.
CandidateApp? candidateFor(List<CandidateApp> candidates, String packageName) =>
    candidates.where((app) => app.packageName == packageName).firstOrNull;

/// FR-03: choose which messaging apps ReplyMate may process. The selection is
/// the privacy boundary and is pushed to the native listener immediately.
class AppSelectionScreen extends ConsumerWidget {
  const AppSelectionScreen({this.embedded = false, super.key});

  /// See `HomeScreen.embedded`: drops the bottom inset the tab bar already
  /// covers.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final candidates = ref.watch(candidateAppsProvider);
    final selected = ref.watch(selectedAppsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(
            theme.brightness,
            primary: theme.colorScheme.primary,
          ),
        ),
        child: SafeArea(
          bottom: !embedded,
          child: candidates.when(
            data: (apps) {
              return AppSurfaces.centered(
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spaceMd,
                    AppTheme.spaceSm,
                    AppTheme.spaceMd,
                    AppTheme.spaceXl,
                  ),
                  children: [
                    ScreenHeader(
                      title: strings.appsTitle,
                      showBack: !embedded,
                      subtitle: apps.isEmpty
                          ? strings.appsNothingYet
                          : strings.appsSelectedOf(
                              selected.length,
                              apps.length,
                            ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    if (apps.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppSurfaces.iconBadge(
                                context,
                                icon: Icons.apps_outlined,
                              ),
                              const SizedBox(height: AppTheme.spaceMd - 4),
                              Text(
                                strings.appsNoneInstalledTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.appsNoneInstalledBody,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12.5,
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
                        strings.appsReadFrom,
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
                            for (
                              var index = 0;
                              index < apps.length;
                              index++
                            ) ...[
                              if (index > 0) const Divider(height: 1),
                              // The launcher icon leads, because the user
                              // recognises the app long before they read the
                              // label (and two apps called "Messages" are only
                              // distinguishable by their icon).
                              CheckboxListTile(
                                value: selected.contains(
                                  apps[index].packageName,
                                ),
                                onChanged: (_) => ref
                                    .read(selectedAppsProvider.notifier)
                                    .toggle(apps[index].packageName),
                                secondary: AppIconTile(
                                  label: apps[index].label,
                                  icon: apps[index].icon,
                                ),
                                title: Text(
                                  apps[index].label,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                // One line, said once: the old subtitle
                                // repeated the same sentence on every row and
                                // pushed the list past the fold.
                                subtitle: Text(
                                  strings.appsNotificationsOnly,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                activeColor: theme.colorScheme.primary,
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
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: AppTheme.spaceSm),
                          Expanded(
                            child: Text(
                              strings.appsWhyListed,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                height: 1.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Column(
                children: [
                  ScreenHeader(title: strings.appsTitle),
                  const SizedBox(height: AppTheme.spaceLg),
                  Text(
                    strings.appsReadFailed,
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
