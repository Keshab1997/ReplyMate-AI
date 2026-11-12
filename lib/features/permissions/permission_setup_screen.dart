import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../../shared/widgets/mascot_face.dart';
import '../../shared/widgets/screen_header.dart';
import 'providers/permission_provider.dart';

/// FR-02: explain why notification access is needed, open the right Settings
/// page, and re-check the state when the user comes back (Android keeps the
/// grant decision entirely inside Settings).
class PermissionSetupScreen extends ConsumerStatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  ConsumerState<PermissionSetupScreen> createState() =>
      _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends ConsumerState<PermissionSetupScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from Settings is a resume: re-read the grant immediately
    // instead of waiting for the user to pull to refresh (USER_FLOWS flow 1).
    if (state == AppLifecycleState.resumed) {
      ref.read(listenerPermissionProvider.notifier).refresh();
      // Overlay access lives in the same Settings app and is just as easy to
      // revoke, so it is re-read on the same resume.
      ref.read(overlayProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(listenerPermissionProvider);
    final overlayEnabled = ref.watch(overlayProvider);
    final theme = Theme.of(context);

    Widget bullet({
      required IconData icon,
      required String title,
      required String body,
      required Color tint,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSurfaces.iconBadge(context, icon: icon, color: tint, size: 34),
          const SizedBox(width: AppTheme.spaceSm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: AppSurfaces.centered(
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceMd,
                AppTheme.spaceSm,
                AppTheme.spaceMd,
                AppTheme.spaceXl,
              ),
              children: [
                ScreenHeader(
                  title: 'Notification access',
                  subtitle: enabled ? 'Granted' : 'Needed for the bubble',
                  trailing: MascotFace(
                    size: 34,
                    glow: false,
                    animate: false,
                    mood: enabled ? MascotMood.happy : MascotMood.alert,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceMd),

                PermissionStatusCard(
                  enabled: enabled,
                  onManage: () => ref
                      .read(listenerPermissionProvider.notifier)
                      .openSettings(),
                ),
                const SizedBox(height: AppTheme.spaceMd),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What this access allows',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spaceSm + 2),
                        bullet(
                          icon: Icons.check_rounded,
                          title: 'Notifications from apps you pick',
                          body:
                              'ReplyMate processes only the apps you select on '
                              'the next screen, uses the text solely to draft '
                              'replies, and never stores conversations.',
                          tint: AppTheme.mint,
                        ),
                        bullet(
                          icon: Icons.block_rounded,
                          title: 'No reading inside apps',
                          body:
                              'No screen capture, no accessibility service, no '
                              'sending messages. You can revoke the access here '
                              'or in Android Settings at any time.',
                          tint: AppTheme.brandBright,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppTheme.spaceMd),
                AppSurfaces.primaryAction(
                  context,
                  label: 'Open Android Settings',
                  onPressed: () => ref
                      .read(listenerPermissionProvider.notifier)
                      .openSettings(),
                  icon: const Icon(Icons.settings_outlined, size: 19),
                ),
                const SizedBox(height: AppTheme.spaceSm),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later - I will paste text manually'),
                ),

                // The optional part comes after the required one, so the manual
                // escape hatch never scrolls out of reach behind it.
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spaceLg),
                  child: Text(
                    'OPTIONAL · FLOATING REPLY BUBBLE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceSm),
                _OverlayAccessCard(
                  granted: overlayEnabled,
                  onOpenSettings: () =>
                      ref.read(overlayProvider.notifier).openSettings(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The overlay card (screen 4 of, FLOATING_OVERLAY.md §6): what "display over other apps" is for here, what it
/// is emphatically *not* for, its current state, and the two things Android 13+
/// additionally requires.
/// Written as an explanation, not a sales pitch: declining it is a supported,
/// explained outcome - the fallback notification is the degraded path, not a
/// broken app.
class _OverlayAccessCard extends StatelessWidget {
  const _OverlayAccessCard({
    required this.granted,
    required this.onOpenSettings,
  });

  final bool granted;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppSurfaces.iconBadge(
                  context,
                  icon: granted
                      ? Icons.check_circle_rounded
                      : Icons.bubble_chart_outlined,
                  color: granted ? AppTheme.mint : scheme.onSurfaceVariant,
                  size: 36,
                ),
                const SizedBox(width: AppTheme.spaceMd - 4),
                Expanded(
                  child: Text(
                    granted
                        ? 'Overlay access granted'
                        : 'Overlay access not granted',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            const Text(
              'A small ReplyMate bubble can float over the app you are in when '
              'a message arrives from an app you selected. Tapping it opens a '
              'panel to draft a reply without leaving the conversation. It is '
              'optional, and off by default.',
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Text(
              'What it does not do',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            const Text(
              'It never reads the screen, the app underneath, or anything '
              'another app displays. It only knows what the notification '
              'already posted. It never sends a message by itself, and it keeps '
              'no message after the panel closes.',
            ),
            const SizedBox(height: AppTheme.spaceMd),
            const Text(
              'On Android 13 and later, notifications must also be allowed, so '
              'the bubble can show its own silent notification and the fallback '
              '"New message from …" notification can appear.',
            ),
            const SizedBox(height: AppTheme.spaceMd),
            if (!granted)
              OutlinedButton(
                onPressed: onOpenSettings,
                child: const Text('Open "Display over other apps"'),
              )
            else
              OutlinedButton(
                onPressed: onOpenSettings,
                child: const Text('Manage overlay access'),
              ),
          ],
        ),
      ),
    );
  }
}
