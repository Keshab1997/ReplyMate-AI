import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/reply_options.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../shared/widgets/choice_chips.dart';
import '../../shared/widgets/mascot_face.dart';
import '../admin/admin_gate_screen.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../app_selection/app_selection_screen.dart';
import '../notifications/providers/notification_providers.dart';
import '../overlay/providers/bubble_providers.dart';
import '../permissions/permission_setup_screen.dart';
import '../permissions/providers/permission_provider.dart';
import 'providers/preferences_provider.dart';

/// Screen 8 plus the privacy screen (9): defaults, permission state, and the
/// privacy explanation with a working "clear local preferences" control.
///
/// Stateful and lifecycle-aware for one reason: the overlay grant can be given
/// or taken away in Android Settings while this screen is alive. Without a
/// resume re-read the "Reply bubble" switch would stay greyed out after the
/// user *did* grant access - the bubble would look broken for a permission
/// reason nobody could see.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-read on entry, not only on first build.
    ref.read(overlayProvider.notifier).refresh();
    ref.read(listenerPermissionProvider.notifier).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(overlayProvider.notifier).refresh();
      ref.read(listenerPermissionProvider.notifier).refresh();
    }
  }

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
  Widget build(BuildContext context) {
    final preferences = ref.watch(preferencesProvider);
    final permissionEnabled = ref.watch(listenerPermissionProvider);
    final overlayEnabled = ref.watch(overlayProvider);
    final bubbleEnabled = ref.watch(bubbleEnabledProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget section(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(top: AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppTheme.spaceSm),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          child,
        ],
      ),
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spaceMd,
              AppTheme.spaceSm,
              AppTheme.spaceMd,
              AppTheme.spaceXl,
            ),
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 19),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Text(
                    'Settings',
                    style: theme.appBarTheme.titleTextStyle?.copyWith(
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),

              // The helper, small, with its state in words: the same face the
              // bubble shows, so the settings screen and the bubble feel like
              // one thing.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceMd - 2),
                  child: Row(
                    children: [
                      MascotFace(
                        size: 44,
                        glow: false,
                        animate: false,
                        mood: bubbleEnabled
                            ? MascotMood.happy
                            : MascotMood.idle,
                      ),
                      const SizedBox(width: AppTheme.spaceMd - 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your helper',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bubbleEnabled
                                  ? 'Bubble on · waits over your chats'
                                  : 'Bubble off · replies still work here',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        bubbleEnabled
                            ? Icons.bubble_chart_rounded
                            : Icons.bubble_chart_outlined,
                        size: 20,
                        color: bubbleEnabled
                            ? AppTheme.mint
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),

              section(
                'Reply style',
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Language',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ChoiceChips<ReplyLanguage>(
                          options: ReplyLanguage.values,
                          selected: preferences.language,
                          labelOf: (language) => language.label,
                          onSelected: (language) => ref
                              .read(preferencesProvider.notifier)
                              .setLanguage(language),
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        Text(
                          'Tone',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ChoiceChips<ReplyTone>(
                          options: ReplyTone.values,
                          selected: preferences.tone,
                          labelOf: (tone) => tone.label,
                          onSelected: (tone) => ref
                              .read(preferencesProvider.notifier)
                              .setTone(tone),
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        Text(
                          'Length',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ChoiceChips<ReplyLength>(
                          options: ReplyLength.values,
                          selected: preferences.length,
                          labelOf: (length) => length.label,
                          onSelected: (length) => ref
                              .read(preferencesProvider.notifier)
                              .setLength(length),
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        Text(
                          'Every screen and the bubble use this style. '
                          'Nothing asks again.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              section(
                'Capture',
                Column(
                  children: [
                    PermissionStatusCard(
                      enabled: permissionEnabled,
                      onManage: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PermissionSetupScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: bubbleEnabled,
                            // Off - and unswitchable - until Android actually
                            // lets us draw over other apps. A switch that
                            // promises something the OS refuses would be the
                            // dishonest version of it.
                            onChanged: overlayEnabled
                                ? (value) => _setBubble(context, ref, value)
                                : null,
                            title: const Text('Floating reply bubble'),
                            subtitle: Text(
                              overlayEnabled
                                  ? 'Shows a bubble over the app you are in '
                                        'when an allowed app sends a message. '
                                        'Off by default; turn it off again any '
                                        'time.'
                                  : 'Needs the optional "Display over other '
                                        'apps" access. Grant it below; the '
                                        'switch turns on by itself when you '
                                        'come back.',
                            ),
                          ),
                          // The fix for "the switch does nothing": the reason
                          // is a permission, so the permission gets a button
                          // *here*, not three screens away.
                          if (!overlayEnabled)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppTheme.spaceMd,
                                0,
                                AppTheme.spaceMd,
                                AppTheme.spaceMd,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: () => ref
                                      .read(overlayProvider.notifier)
                                      .openSettings(),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: const Text('Grant overlay access'),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.spaceSm,
                              0,
                              AppTheme.spaceSm,
                              AppTheme.spaceSm,
                            ),
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AppSelectionScreen(),
                                ),
                              ),
                              icon: const Icon(
                                Icons.widgets_outlined,
                                size: 18,
                              ),
                              label: const Text('Supported apps'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              section(
                'Privacy',
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Promise(
                          icon: Icons.delete_outline_rounded,
                          title: 'Messages are never stored',
                          body:
                              'Nothing you reply to is written to disk or '
                              'to the logs.',
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        _Promise(
                          icon: Icons.pan_tool_alt_outlined,
                          title: 'Nothing is sent by itself',
                          body:
                              'ReplyMate drafts. You press the button that '
                              'sends.',
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
                            fontSize: 11,
                            height: 1.55,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
              ),

              if (ref.watch(firebaseReadyProvider))
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spaceLg),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminGateScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Admin'),
                  ),
                ),
            ],
          ),
        ),
      ),
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
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: AppTheme.mint.withValues(alpha: 0.14),
          ),
          child: Icon(icon, size: 15, color: AppTheme.mint),
        ),
        const SizedBox(width: AppTheme.spaceSm + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  fontSize: 10.5,
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
