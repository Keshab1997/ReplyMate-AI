import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'theme/app_theme.dart';

class ReplyMateApp extends StatelessWidget {
  const ReplyMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReplyMate AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const StartupGate(),
    );
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
