import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/permission_status_card.dart';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(listenerPermissionProvider);
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
          ],
        ),
      ),
    );
  }
}
