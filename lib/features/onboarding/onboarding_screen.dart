import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/widgets/mascot_face.dart';
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
      'Pick the language and tone for every reply - friendly, casual, '
          'professional, polite, funny, short and direct, Premika or Premik.',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spaceLg,
              AppTheme.spaceMd,
              AppTheme.spaceLg,
              AppTheme.spaceLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Meet the helper before being asked for anything: the honest
                // ordering FR-01 asks for, shown as a character rather than a
                // paragraph of policy.
                Center(child: MascotFace(size: 76, mood: MascotMood.idle)),
                const SizedBox(height: AppTheme.spaceSm),
                Center(
                  child: Text(
                    'ReplyMate AI',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Center(
                  child: Text(
                    'Your AI reply assistant for everyday conversations.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceLg),
                Expanded(
                  child: ListView.separated(
                    itemCount: _points.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTheme.spaceSm),
                    itemBuilder: (context, index) {
                      final (icon, title, body) = _points[index];
                      return Container(
                        padding: const EdgeInsets.all(AppTheme.spaceMd - 2),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.045)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppTheme.cardRadius,
                          ),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : theme.colorScheme.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: AppTheme.brand.withValues(
                                  alpha: isDark ? 0.22 : 0.12,
                                ),
                              ),
                              child: Icon(
                                icon,
                                size: 16,
                                color: AppTheme.brandBright,
                              ),
                            ),
                            const SizedBox(width: AppTheme.spaceMd - 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    body,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.5,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    gradient: AppTheme.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brand.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: () => _complete(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    child: const Text('Get started'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
