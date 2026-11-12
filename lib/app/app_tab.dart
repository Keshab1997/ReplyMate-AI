import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import 'theme/app_icons.dart';

/// The four places in the app, and the order they sit in the bottom bar.
enum AppTab {
  home,
  reply,
  apps,
  settings;

  IconData get icon => switch (this) {
    AppTab.home => AppIcons.homeOutlined,
    AppTab.reply => AppIcons.replyOutlined,
    AppTab.apps => AppIcons.appsOutlined,
    AppTab.settings => AppIcons.settingsOutlined,
  };

  IconData get selectedIcon => switch (this) {
    AppTab.home => AppIcons.home,
    AppTab.reply => AppIcons.reply,
    AppTab.apps => AppIcons.apps,
    AppTab.settings => AppIcons.settings,
  };

  String label(AppStrings strings) => switch (this) {
    AppTab.home => strings.tabHome,
    AppTab.reply => strings.tabReply,
    AppTab.apps => strings.tabApps,
    AppTab.settings => strings.tabSettings,
  };
}

/// Which tab the shell is showing.
/// A provider rather than a callback threaded down the tree: Home's
/// "Generate a reply" and the app-selection shortcut both sit several widgets
/// below the shell, and passing a callback to each is how a tab bar ends up
/// reinvented in every screen that wants one.
final NotifierProvider<AppTabNotifier, AppTab> appTabProvider =
    NotifierProvider<AppTabNotifier, AppTab>(AppTabNotifier.new);

class AppTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void select(AppTab tab) => state = tab;
}
