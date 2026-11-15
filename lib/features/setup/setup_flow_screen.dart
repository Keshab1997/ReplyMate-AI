import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_shell.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/reply_options.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/choice_chips.dart';
import '../../shared/widgets/permission_status_card.dart';
import '../../shared/widgets/section_label.dart';
import '../app_selection/app_selection_screen.dart';
import '../app_selection/providers/selected_apps_provider.dart';
import '../permissions/providers/permission_provider.dart';
import '../settings/providers/preferences_provider.dart';

/// The four steps, in the order they are shown.
///
/// The order is the argument: explain first (welcome), then the two choices
/// that cost nothing (language and style), then the one thing Android has to be
/// asked for (notification access), then a summary of what was chosen. Asking
/// for a permission before the user knows what the app is would be the cheap
/// move; this flow does not make it.
enum SetupStep { welcome, style, capture, ready }

/// The first-run setup: what a new install sees once the welcome points have
/// been read, so that "open the app" does not mean "land on an empty home
/// screen and work out six switches yourself".
///
/// Two rules keep it honest:
///  * every step has a working default, so nothing here is a wall - the
///    secondary action always gets the user into the app;
///  * leaving early does **not** mark setup as done. The flag means "this person
///    went through it", not "this person dismissed it once", so a half-finished
///    setup comes back on the next launch instead of disappearing for ever.
class SetupFlowScreen extends ConsumerStatefulWidget {
  const SetupFlowScreen({this.startAt = SetupStep.welcome, super.key});

  /// Tests and the screenshot registry start at a step other than the first.
  final SetupStep startAt;

  @override
  ConsumerState<SetupFlowScreen> createState() => _SetupFlowScreenState();
}

class _SetupFlowScreenState extends ConsumerState<SetupFlowScreen> {
  static const List<SetupStep> _steps = SetupStep.values;

  late final PageController _pages = PageController(
    initialPage: widget.startAt.index,
  );
  late SetupStep _step = widget.startAt;

  /// Guards the double tap that would push the shell twice.
  bool _leaving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _isLast => _step == _steps.last;

  void _goTo(SetupStep step) {
    if (step == _step) return;
    setState(() => _step = step);
    _pages.animateToPage(
      step.index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_isLast) {
      _enterApp(markDone: true);
      return;
    }
    _goTo(_steps[_step.index + 1]);
  }

  void _back() {
    if (_step.index == 0) return;
    _goTo(_steps[_step.index - 1]);
  }

  /// The single exit. `markDone` is false only for "Later", which deliberately
  /// leaves the flag unset so the next launch offers the setup again.
  Future<void> _enterApp({required bool markDone}) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    if (markDone) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.prefSetupDone, true);
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: AppSurfaces.centered(
            Column(
              children: [
                _SetupTopBar(
                  step: _step,
                  index: _step.index + 1,
                  total: _steps.length,
                  strings: strings,
                  onBack: _step.index == 0 ? null : _back,
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (page) =>
                        setState(() => _step = _steps[page]),
                    children: [
                      _WelcomeStep(strings: strings, onStart: _next),
                      _StyleStep(strings: strings),
                      _CaptureStep(strings: strings),
                      _ReadyStep(strings: strings),
                    ],
                  ),
                ),
                _SetupActions(
                  label: switch (_step) {
                    SetupStep.welcome => strings.setupStart,
                    SetupStep.ready => strings.setupFinish,
                    _ => strings.setupNext,
                  },
                  icon: _isLast
                      ? const Icon(AppIcons.reply, size: 19)
                      : const Icon(AppIcons.forward, size: 19),
                  busy: _leaving,
                  onPressed: _next,
                  secondary: _step == SetupStep.welcome
                      ? TextButton(
                          onPressed: _leaving
                              ? null
                              : () => _enterApp(markDone: false),
                          child: Text(strings.setupLater),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back arrow, step counter and the progress bar. One row, so the eye reads the
/// page position once instead of counting dots in three places.
class _SetupTopBar extends StatelessWidget {
  const _SetupTopBar({
    required this.step,
    required this.index,
    required this.total,
    required this.strings,
    required this.onBack,
  });

  final SetupStep step;
  final int index;
  final int total;
  final AppStrings strings;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceSm,
        AppTheme.spaceSm,
        AppTheme.spaceMd,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (onBack == null)
                const SizedBox(width: 44)
              else
                IconButton(
                  onPressed: onBack,
                  tooltip: strings.back,
                  icon: const Icon(AppIcons.back),
                ),
              Expanded(
                child: Center(
                  child: Text(
                    strings.setupStepCount(index, total),
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 44),
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceMd - 4,
            ),
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i <= step.index
                            ? null
                            : scheme.surfaceContainerHighest,
                        gradient: i <= step.index
                            ? AppTheme.primaryGradient
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned action at the bottom: one strong button, never more.
class _SetupActions extends StatelessWidget {
  const _SetupActions({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.busy,
    this.secondary,
  });

  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final bool busy;

  /// The way out of the first step. Pinned here rather than inside the page, so
  /// it never scrolls out of reach - a user who does not want the setup should
  /// not have to hunt for the button that says so.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceLg,
        AppTheme.spaceSm,
        AppTheme.spaceLg,
        AppTheme.spaceMd,
      ),
      child: Column(
        children: [
          AppSurfaces.primaryAction(
            context,
            label: label,
            icon: icon,
            onPressed: busy ? null : onPressed,
          ),
          ?secondary,
        ],
      ),
    );
  }
}

/// The shared skeleton of a step: illustration, title, body, then the step's
/// own content. Scrolling is inside the page, so a short phone never pushes the
/// primary action below the fold.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.hero,
    required this.title,
    required this.body,
    required this.children,
  });

  final String hero;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).height < 800;
    const padding = EdgeInsets.fromLTRB(
      AppTheme.spaceLg,
      AppTheme.spaceMd,
      AppTheme.spaceLg,
      AppTheme.spaceMd,
    );
    // A short step (the welcome) is centred in the space it has, and a long one
    // (the style chips) scrolls. Without the minHeight the welcome left half a
    // page of nothing between the card and the button, which reads as a
    // rendering bug rather than as breathing room.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - padding.vertical,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroImage(asset: hero, compact: compact),
              SizedBox(height: compact ? AppTheme.spaceMd : AppTheme.spaceLg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: compact ? 24 : 26,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm + 2),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: compact ? AppTheme.spaceMd : AppTheme.spaceLg),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// One generated illustration, cropped to a banner and rounded like every other
/// surface in the app. The pictures are 3D renders on the same navy/blue the
/// dark theme uses, so they read as part of the app rather than stickers
/// dropped on it.
class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.asset, required this.compact});

  final String asset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: compact ? 200 : 260),
        child: AspectRatio(
          aspectRatio: 16 / 11,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius + 6),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: isDark ? 0.28 : 0.16),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius + 6),
              child: Image.asset(asset, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.strings, required this.onStart});

  final AppStrings strings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      hero: 'assets/setup/setup_welcome.png',
      title: strings.setupWelcomeTitle,
      body: strings.setupWelcomeBody,
      children: [
        // A table of contents, not a sales pitch: the three things the flow
        // will ask for, so the permission step is not a surprise three taps in.
        Card(
          child: Column(
            children: [
              _PreviewRow(
                icon: AppIcons.language,
                tint: AppTheme.brandBright,
                text: strings.setupWelcomePointStyle,
              ),
              const Divider(height: 1),
              _PreviewRow(
                icon: AppIcons.notification,
                tint: AppTheme.cyan,
                text: strings.setupWelcomePointCapture,
              ),
              const Divider(height: 1),
              _PreviewRow(
                icon: Icons.apps_rounded,
                tint: AppTheme.mint,
                text: strings.setupWelcomePointApps,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.tint,
    required this.text,
  });

  final IconData icon;
  final Color tint;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceMd - 2,
        vertical: AppTheme.spaceSm + 4,
      ),
      child: Row(
        children: [
          AppSurfaces.iconBadge(context, icon: icon, color: tint, size: 32),
          const SizedBox(width: AppTheme.spaceMd - 4),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Language and reply style, the two settings that change every reply the app
/// will ever write. Saved immediately: a user who closes the app mid-setup keeps
/// what they already chose.
class _StyleStep extends ConsumerWidget {
  const _StyleStep({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final preferences = ref.watch(preferencesProvider);
    return _StepScaffold(
      hero: 'assets/setup/setup_welcome.png',
      title: strings.setupStyleTitle,
      body: strings.setupStyleBody,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(strings.setupUiLanguage),
                ChoiceChips<AppLanguage>(
                  options: AppLanguage.values,
                  selected: language,
                  labelOf: (option) => option.label,
                  onSelected: (option) => ref
                      .read(appLanguageProvider.notifier)
                      .setLanguage(option),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                SectionLabel(strings.setupReplyLanguage),
                ChoiceChips<ReplyLanguage>(
                  options: ReplyLanguage.values,
                  selected: preferences.language,
                  labelOf: (option) => option.label,
                  onSelected: (option) => ref
                      .read(preferencesProvider.notifier)
                      .setLanguage(option),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                SectionLabel(strings.setupTone),
                ChoiceChips<ReplyTone>(
                  options: ReplyTone.values,
                  selected: preferences.tone,
                  labelOf: (option) => option.label,
                  onSelected: (option) =>
                      ref.read(preferencesProvider.notifier).setTone(option),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                SectionLabel(strings.setupLength),
                ChoiceChips<ReplyLength>(
                  options: ReplyLength.values,
                  selected: preferences.length,
                  labelOf: (option) => option.label,
                  onSelected: (option) =>
                      ref.read(preferencesProvider.notifier).setLength(option),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The one step that needs Android: notification access, which apps are
/// allowed, and the optional bubble. The permission card is the same widget
/// Home uses, so the two can never tell different stories about the same grant.
class _CaptureStep extends ConsumerWidget {
  const _CaptureStep({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(listenerPermissionProvider);
    final selectedApps = ref.watch(selectedAppsProvider);
    final theme = Theme.of(context);
    return _StepScaffold(
      hero: 'assets/setup/setup_capture.png',
      title: strings.setupCaptureTitle,
      body: strings.setupCaptureBody,
      children: [
        PermissionStatusCard(
          enabled: enabled,
          strings: strings,
          onManage: () =>
              ref.read(listenerPermissionProvider.notifier).openSettings(),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppSurfaces.iconBadge(
                      context,
                      icon: Icons.apps_rounded,
                      color: AppTheme.cyan,
                    ),
                    const SizedBox(width: AppTheme.spaceMd - 4),
                    Expanded(
                      child: Text(
                        selectedApps.isEmpty
                            ? strings.setupAppsNone
                            : strings.setupAppsChosen(selectedApps.length),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceMd),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AppSelectionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: Text(strings.setupChooseApps),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Text(
          strings.setupCaptureOptional,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The summary, then the one button that opens the app. Reading it back is the
/// point: the user sees "here is what I just chose" instead of being dropped
/// onto a home screen and hoping the choices took.
class _ReadyStep extends ConsumerWidget {
  const _ReadyStep({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(listenerPermissionProvider);
    final selectedApps = ref.watch(selectedAppsProvider);
    final preferences = ref.watch(preferencesProvider);
    final theme = Theme.of(context);
    final style = [
      preferences.language.label,
      preferences.tone.label,
      preferences.length.label,
    ].join(' · ');
    return _StepScaffold(
      hero: 'assets/setup/setup_ready.png',
      title: strings.setupReadyTitle,
      body: strings.setupReadyBody,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.setupReadySummary,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceSm + 2),
                _SummaryRow(
                  icon: enabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  tint: enabled ? AppTheme.mint : AppTheme.amber,
                  text: strings.setupNotifications(enabled ? 1 : 0),
                ),
                _SummaryRow(
                  icon: Icons.apps_rounded,
                  tint: AppTheme.cyan,
                  text: selectedApps.isEmpty
                      ? strings.setupAppsNone
                      : strings.setupAppsChosen(selectedApps.length),
                ),
                _SummaryRow(
                  icon: Icons.tune_rounded,
                  tint: AppTheme.brandBright,
                  text: style,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Text(
          strings.setupChangeLater,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.tint,
    required this.text,
  });

  final IconData icon;
  final Color tint;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: AppTheme.spaceSm + 2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
