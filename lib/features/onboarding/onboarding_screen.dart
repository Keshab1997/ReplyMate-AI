import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/widgets/mascot_face.dart';
import '../home/home_screen.dart';

/// FR-01: explain purpose, limitations and permissions before asking for
/// anything. Honest claims only - the same limitations the README makes, in
/// plain language, inside one calm and readable welcome flow.
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
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: AppSurfaces.centered(
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceLg,
                AppTheme.spaceMd,
                AppTheme.spaceLg,
                AppTheme.spaceLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Meet the helper before being asked for anything. The face,
                  // not another illustration, is the brand.
                  const Center(
                    child: MascotFace(size: 88, mood: MascotMood.idle),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Center(
                    child: AppSurfaces.pill(
                      context,
                      accent: true,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: AppTheme.brandBright,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'YOUR AI REPLY ASSISTANT',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(
                    'ReplyMate AI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 32,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    'Thoughtful replies in your language,\nwith you always in control.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceLg),

                  // One grouped surface is quieter than four competing cards.
                  // It scrolls independently so the primary action is never
                  // pushed below the fold on a short screen.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Card(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < _points.length;
                              index++
                            ) ...[
                              if (index > 0) const Divider(height: 1),
                              _OnboardingPoint(point: _points[index]),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  AppSurfaces.primaryAction(
                    context,
                    label: 'Get started',
                    onPressed: () => _complete(context),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  ),
                  const SizedBox(height: AppTheme.spaceMd - 4),
                  Text(
                    'You choose what ReplyMate can access.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPoint extends StatelessWidget {
  const _OnboardingPoint({required this.point});

  final (IconData, String, String) point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, body) = point;
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSurfaces.iconBadge(context, icon: icon),
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
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
