import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../reply/presentation/chat_reply_styles_card.dart';
import '../../reply/presentation/own_key_card.dart';
import 'ai_usage_card.dart';
import 'settings_sub_screen.dart';

/// Settings → AI key & usage. Where the key comes from, today's local request
/// count, and the styles saved per chat.
///
/// These cards keep the AI controls together instead of scattering them across
/// several separate stops in one long scroll.
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
