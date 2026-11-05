import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../home/home_screen.dart';

/// FR-01: explain purpose, limitations and permissions before asking for
/// anything. Honest claims only - the same three limitations the README
/// makes, in plain language.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const List<(IconData, String, String)> _points = [
    (
      Icons.smart_toy_outlined,
      'Replies you approve, always',
      'ReplyMate suggests replies. You review, edit and send - the app never '
          'sends a message on its own.',
    ),
    (
      Icons.notifications_outlined,
      'Works from notifications',
      'With your permission it reads notifications from apps you select. '
          'Some apps hide or shorten notification text; when that happens '
          'ReplyMate says so instead of guessing.',
    ),
    (
      Icons.translate_rounded,
      'Bengali, Hindi and English',
      'Pick the language and tone for every reply: friendly, casual, '
          'professional, polite, funny, or short and direct.',
    ),
    (
      Icons.lock_outline_rounded,
      'Privacy first',
      'Message text is sent to an AI service only when you ask for '
          'suggestions. Nothing is stored as conversation history.',
    ),
  ];

  Future<void> _complete(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefOnboardingDone, true);
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTheme.spaceXl),
              Text(
                'ReplyMate AI',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                'Your AI-powered reply assistant for everyday conversations.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppTheme.spaceXl),
              Expanded(
                child: ListView.separated(
                  itemCount: _points.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppTheme.spaceLg),
                  itemBuilder: (context, index) {
                    final (icon, title, body) = _points[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 28),
                        const SizedBox(width: AppTheme.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: AppTheme.spaceXs),
                              Text(
                                body,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              FilledButton(
                onPressed: () => _complete(context),
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
