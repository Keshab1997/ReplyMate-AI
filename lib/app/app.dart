import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/overlay/presentation/overlay_panel_screen.dart';
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

/// Sends first-run users through onboarding (FR-01) and everyone else
/// straight home. Reading one boolean keeps startup free of network or
/// SDK work (the invariant docify taught us: nothing optional holds the
/// first frame hostage).
class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  Future<bool> _onboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.prefOnboardingDone) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboardingDone(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true
            ? const HomeScreen()
            : const OnboardingScreen();
      },
    );
  }
}
