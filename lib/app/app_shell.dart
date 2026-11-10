import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_tab.dart';
import 'theme/app_theme.dart';
import '../core/l10n/app_strings.dart';
import '../features/app_selection/app_selection_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notifications/models/captured_notification.dart';
import '../features/reply/presentation/reply_composer_screen.dart';
import '../features/settings/settings_screen.dart';

/// The app's one screen, with the four destinations along the bottom.
///
/// The children are built with `embedded: true`, which drops their own
/// `Scaffold`: a Scaffold inside a Scaffold stacks two `SafeArea`s and leaves
/// a dead band above the tab bar. The shell owns the chrome; each tab owns
/// only its content.
///
/// All four are kept alive by `IndexedStack` rather than rebuilt on switch, so
/// a half-typed reply survives a trip to Settings and back - the same reason
/// a native tab bar keeps its fragments.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    this.initialTab = AppTab.home,
    this.initialNotification,
    super.key,
  });

  /// Where to start. A tap on the fallback notification asks for the composer
  /// with the waiting message already in it.
  final AppTab initialTab;

  /// The message a fallback notification handed over, if any.
  final CapturedNotification? initialNotification;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    if (widget.initialTab != AppTab.home) {
      // Deferred by a frame on purpose: Riverpod refuses a provider write made
      // while the tree is building, and initState still counts as building. A
      // fallback notification that opens straight into the Reply tab would
      // otherwise throw before the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(appTabProvider.notifier).select(widget.initialTab);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(appTabProvider);
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: IndexedStack(
          index: tab.index,
          children: <Widget>[
            const HomeScreen(embedded: true),
            ReplyComposerScreen(
              key: const ValueKey<String>('tab-reply'),
              embedded: true,
              initialNotification: widget.initialNotification,
            ),
            const AppSelectionScreen(embedded: true),
            const SettingsScreen(embedded: true),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (index) =>
            ref.read(appTabProvider.notifier).select(AppTab.values[index]),
        // No explicit backgroundColor: the bar takes the theme's surface, so
        // dark mode stays dark without a second colour to keep in step.
        destinations: <Widget>[
          for (final destination in AppTab.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label(strings),
            ),
        ],
      ),
    );
  }
}
