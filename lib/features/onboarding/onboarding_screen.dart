import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_icons.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/widgets/brand_icon.dart';
import '../../shared/widgets/mascot_face.dart';
import '../home/home_screen.dart';

/// FR-01: explain purpose, limitations and permissions before asking for
/// anything. Honest claims only - the same limitations the README makes, in
/// plain language, inside one calm and readable welcome flow.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const List<(BrandIconType, String, String)> _points = [
    (
      BrandIconType.reply,
      'Replies you approve, always',
      'ReplyMate suggests replies. You review, edit and send - the app never '
          'sends a message on its own.',
    ),
    (
      BrandIconType.notification,
      'Works from notifications',
      'With your permission it reads notifications from apps you select. '
          'Some apps hide or shorten notification text; when that happens '
          'ReplyMate says so instead of guessing.',
    ),
    (
      BrandIconType.language,
      'Bengali, Hindi and English',
      'Pick the language and tone for every reply - friendly, casual, '
          'professional, polite, funny, short and direct, Premika or Premik.',
    ),
    (
      BrandIconType.privacy,
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
    final compact = MediaQuery.sizeOf(context).height < 900;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: SafeArea(
          child: AppSurfaces.centered(
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppTheme.spaceLg,
                compact ? AppTheme.spaceSm : AppTheme.spaceMd,
                AppTheme.spaceLg,
                compact ? AppTheme.spaceMd : AppTheme.spaceLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Meet the helper before being asked for anything. The face,
                  // not another illustration, is the brand.
                  Center(
                    child: MascotFace(
                      size: compact ? 64 : 88,
                      mood: MascotMood.idle,
                    ),
                  ),
                  SizedBox(
                    height: compact ? AppTheme.spaceSm : AppTheme.spaceMd,
                  ),
                  Center(
                    child: AppSurfaces.pill(
                      context,
                      accent: true,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.generate,
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
                  SizedBox(
                    height: compact ? AppTheme.spaceMd - 4 : AppTheme.spaceMd,
                  ),
                  Text(
                    'ReplyMate AI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: compact ? 30 : 32,
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
                  SizedBox(
                    height: compact ? AppTheme.spaceMd : AppTheme.spaceLg,
                  ),

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
                    icon: const Icon(AppIcons.forward, size: 19),
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

  final (BrandIconType, String, String) point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, body) = point;
    final isDark = theme.brightness == Brightness.dark;
    final foreground = isDark ? AppTheme.brandBright : AppTheme.brand;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSurfaces.iconBadge(
            context,
            color: foreground,
            child: BrandIcon(type: icon, color: foreground),
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
