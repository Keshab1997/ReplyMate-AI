import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../reply/presentation/chat_reply_styles_card.dart';
import '../../reply/presentation/own_key_card.dart';
import 'ai_usage_card.dart';
import 'settings_sub_screen.dart';

/// Settings → AI key & usage. Where the key comes from, what today has cost, and
/// the styles saved per chat.
///
/// These three cards answer the same question - "what is allowed to spend a
/// request on my behalf, and on what" - so they sit together instead of being
/// three separate stops in one long scroll.
class AiScreen extends ConsumerWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return SettingsSubScreen(
      title: strings.ownKeySection,
      subtitle: strings.settingsAiHint,
      children: <Widget>[
        SettingsSection(
          topSpace: AppTheme.spaceSm,
          label: strings.ownKeySection,
          child: const OwnKeyCard(),
        ),
        SettingsSection(
          label: strings.aiUsageSection,
          child: const AiUsageCard(),
        ),
        SettingsSection(
          label: strings.chatStylesSection,
          child: const ChatReplyStylesCard(),
        ),
      ],
    );
  }
}
