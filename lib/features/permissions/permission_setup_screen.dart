import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../../shared/widgets/section_label.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Notification access')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          children: [
            PermissionStatusCard(
              enabled: enabled,
              onManage: () =>
                  ref.read(listenerPermissionProvider.notifier).openSettings(),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What this access allows',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    const Text(
                      'Android shows ReplyMate the notifications you receive. '
                      'ReplyMate processes only the apps you select on the '
                      'next screen, uses the text solely to draft replies, '
                      'and never stores conversations.',
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Text(
                      'What it does not allow',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    const Text(
                      'No reading inside apps, no screen capture, no sending '
                      'messages. You can revoke the access here or in Android '
                      'Settings at any time.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            FilledButton(
              onPressed: () =>
                  ref.read(listenerPermissionProvider.notifier).openSettings(),
              child: const Text('Open Android Settings'),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later - I will paste text manually'),
            ),
            // The optional part comes after the required one, so the manual
            // escape hatch never scrolls out of reach behind it.
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Optional: floating reply bubble'),
            _OverlayAccessCard(
              granted: overlayEnabled,
              onOpenSettings: () =>
                  ref.read(overlayProvider.notifier).openSettings(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The overlay card (screen 4 of docs/SCREEN_SPECIFICATIONS.md, docs/
/// FLOATING_OVERLAY.md §6): what "display over other apps" is for here, what it
/// is emphatically *not* for, its current state, and the two things Android 13+
/// additionally requires.
///
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
                Icon(
                  granted
                      ? Icons.check_circle_rounded
                      : Icons.bubble_chart_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.spaceSm),
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
