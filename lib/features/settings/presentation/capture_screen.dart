import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/brand_icon.dart';
import '../../../shared/widgets/choice_chips.dart';
import '../../../shared/widgets/permission_status_card.dart';
import '../../app_selection/app_selection_screen.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../overlay/providers/bubble_providers.dart';
import '../../permissions/permission_setup_screen.dart';
import '../../permissions/providers/permission_provider.dart';
import '../../screen_reading/providers/screen_reading_provider.dart';
import '../../screen_reading/widgets/screen_reading_status_card.dart';
import 'settings_sub_screen.dart';

/// Settings → Capture & access. Everything that decides *where* a message may
/// come from: notification access, the floating bubble, screen reading and the
/// app allowlist.
///
/// It is a `ConsumerStatefulWidget` for one reason the old single screen had:
/// the overlay grant can be given or taken away in Android's own settings while
/// this screen is alive. Without a resume re-read the bubble switch would stay
/// greyed out after the user *did* grant access - the bubble would look broken
/// for a permission reason nobody could see.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-read on entry, not only on first build.
    ref.read(overlayProvider.notifier).refresh();
    ref.read(listenerPermissionProvider.notifier).refresh();
    ref.read(screenReadingAvailableProvider.notifier).refresh();
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
      ref.read(screenReadingAvailableProvider.notifier).refresh();
    }
  }

  /// Turns the floating reply bubble on or off (default off).
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

  /// Opens Android's accessibility screen. Always available, not only when the
  /// grant is missing: the toggle has to be turned off and on again after a
  /// config change, which is something you do while the grant is still there.
  Future<void> _openAccessibilitySettings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final opened = await ref
        .read(notificationsBridgeProvider)
        .openAccessibilitySettings();
    if (!context.mounted) return;
    if (opened == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This phone has no accessibility screen to open. '
            'Look for it under Settings \u2192 Accessibility.',
          ),
        ),
      );
    }
  }

  /// Turns screen reading on or off (default off).
  /// Turning it **on** shows the disclosure first and waits for a real
  /// confirmation: this is the one feature that reads text off the screen
  /// rather than out of a notification, and "I agreed to that" has to be an
  /// answer the user gave, not a side effect of tapping a switch. A refusal
  /// leaves the switch exactly where it was.
  Future<void> _setScreenReading(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    if (enabled) {
      final strings = ref.read(appStringsProvider);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.screenReadingDisclosureTitle),
          content: Text(strings.screenReadingDisclosureBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(screenReadingProvider.notifier).setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final permissionEnabled = ref.watch(listenerPermissionProvider);
    final overlayEnabled = ref.watch(overlayProvider);
    final bubbleEnabled = ref.watch(bubbleEnabledProvider);
    final bubbleAutoHide = ref.watch(bubbleAutoHideProvider);
    final bubblePreview = ref.watch(bubblePreviewProvider);
    final screenReading = ref.watch(screenReadingProvider);
    final screenReadingAvailable = ref.watch(screenReadingAvailableProvider);
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);

    return SettingsSubScreen(
      title: strings.captureSection,
      subtitle: strings.settingsCaptureHint,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.spaceSm),
          child: Column(
            children: <Widget>[
              PermissionStatusCard(
                enabled: permissionEnabled,
                strings: strings,
                onManage: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PermissionSetupScreen(),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      value: bubbleEnabled,
                      secondary: AppSurfaces.iconBadge(
                        context,
                        icon: AppIcons.bubble,
                        size: 36,
                      ),
                      // Off - and unswitchable - until Android actually lets us
                      // draw over other apps. A switch that promises something
                      // the OS refuses would be the dishonest version of it.
                      onChanged: overlayEnabled
                          ? (value) => _setBubble(context, ref, value)
                          : null,
                      title: Text(strings.bubbleSwitchTitle),
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
                    // Only meaningful while the bubble exists: a preview or a
                    // hide-timer for a bubble that is switched off would be a
                    // setting that cannot do anything.
                    if (bubbleEnabled) ...<Widget>[
                      const Divider(height: 1),
                      // Off by default, and deliberately not bundled with the
                      // bubble switch: this is the only place message text
                      // reaches the screen outside the panel, so it is a
                      // separate yes.
                      SwitchListTile(
                        value: bubblePreview,
                        secondary: AppSurfaces.iconBadge(
                          context,
                          icon: AppIcons.edit,
                          size: 36,
                        ),
                        onChanged: (value) => ref
                            .read(bubblePreviewProvider.notifier)
                            .setEnabled(value),
                        title: const Text('Show a preview'),
                        subtitle: const Text(
                          'Shows the sender and the first line beside '
                          'the bubble. Off by default: anyone glancing '
                          'at your screen can read it. Hidden on the '
                          'lock screen and never saved.',
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spaceMd,
                          AppTheme.spaceSm,
                          AppTheme.spaceMd,
                          AppTheme.spaceSm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    'Hide the bubble after',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                Text(
                                  bubbleAutoHide == 0
                                      ? 'Never'
                                      : '$bubbleAutoHide min',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppTheme.spaceXs),
                            Text(
                              'A bubble nobody replies to tidies '
                              'itself away. The message is not '
                              'lost - a new one brings it back.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spaceSm),
                            ChoiceChips<int>(
                              options: AppConstants.bubbleAutoHideOptions,
                              selected: bubbleAutoHide,
                              labelOf: (minutes) =>
                                  minutes == 0 ? 'Never' : '$minutes min',
                              onSelected: (minutes) => ref
                                  .read(bubbleAutoHideProvider.notifier)
                                  .setMinutes(minutes),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    // Screen reading: the only feature here that can see text
                    // the platform never hands us, so it asks twice - once on
                    // Android's own accessibility screen, and once here, in
                    // words, before it is ever switched on.
                    SwitchListTile(
                      value: screenReading && screenReadingAvailable,
                      secondary: AppSurfaces.iconBadge(
                        context,
                        size: 36,
                        child: BrandIcon(
                          type: BrandIconType.screenReading,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      onChanged: screenReadingAvailable
                          ? (value) => _setScreenReading(context, ref, value)
                          : null,
                      title: Text(strings.screenReadingTitle),
                      subtitle: Text(
                        screenReadingAvailable
                            ? strings.screenReadingSubtitle
                            : strings.screenReadingNeedsPermission,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spaceMd,
                        0,
                        AppTheme.spaceMd,
                        AppTheme.spaceMd,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openAccessibilitySettings(context, ref),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(strings.screenReadingOpenSettings),
                            ),
                          ),
                          if (!screenReadingAvailable) ...<Widget>[
                            const SizedBox(height: AppTheme.spaceSm),
                            Text(
                              strings.screenReadingBlocked,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                height: 1.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Shown once Android has granted access: that is the only
                    // point at which "it reads nothing" is a question about the
                    // reading rather than the grant.
                    if (screenReadingAvailable) const ScreenReadingStatusCard(),
                    // The fix for "the switch does nothing": the reason is a
                    // permission, so the permission gets a button *here*, not
                    // three screens away.
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
                        icon: const Icon(Icons.widgets_outlined, size: 18),
                        label: Text(strings.appsTitle),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
