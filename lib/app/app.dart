import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/overlay/presentation/overlay_panel_screen.dart';
import '../features/overlay/providers/overlay_providers.dart';
import '../features/reply/presentation/reply_composer_screen.dart';
import 'app_routes.dart';
import 'theme/app_theme.dart';

class ReplyMateApp extends StatelessWidget {
  const ReplyMateApp({super.key, this.initialRoute});

  /// Boot route override, for tests and the in-app preview. In production this
  /// stays null on purpose: Flutter then uses the route the platform asked for,
  /// which is how `OverlayPanelActivity` opens `/overlay` while a normal tap on
  /// the launcher opens `/`.
  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReplyMate AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      initialRoute: initialRoute,
      onGenerateRoute: _routeFor,
    );
  }

  static Route<dynamic>? _routeFor(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.overlay:
        // The reply panel: translucent, sheet-like, and only reachable from
        // the bubble (docs/FLOATING_OVERLAY.md §4.2).
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const OverlayPanelScreen(),
        );
      case AppRoutes.home:
        // Everything else goes through onboarding-or-home as before.
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const StartupGate(),
        );
      default:
        return null;
    }
  }
}

/// Sends first-run users through onboarding (FR-01), a fallback-notification
/// tap straight to the prefilled composer, and everyone else home.
///
/// Both reads are local and cheap, and neither is allowed to hold the first
/// frame hostage (the invariant docify taught us):
///  - the onboarding flag is one boolean from SharedPreferences;
///  - the pending overlay context is a *non-blocking* watch. While it is still
///    resolving the normal screen renders, and it swaps to the composer only
///    if a fallback notification was actually waiting. Startup therefore never
///    waits on the native layer, and a native layer that never answers costs
///    nothing.
class StartupGate extends ConsumerWidget {
  const StartupGate({super.key});

  Future<bool> _onboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.prefOnboardingDone) ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value` is null while loading - and stays null if the native side never
    // answers. No spinner, no blocked frame.
    final replyContext = ref.watch(overlayContextProvider).value;
    return FutureBuilder<bool>(
      future: _onboardingDone(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != true) {
          return const OnboardingScreen();
        }
        final reply = replyContext;
        // A fallback notification is a request to answer a message, so it
        // opens the composer prefilled instead of Home. A `bubble` context is
        // not consumed here - that launch has its own panel route.
        if (reply != null && !reply.opensPanel) {
          return ReplyComposerScreen(initialNotification: reply.notification);
        }
        return const HomeScreen();
      },
    );
  }
}
