import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/l10n/app_strings.dart';
import '../../memory/widgets/conversation_memory_card.dart';
import '../../reply/presentation/saved_replies_card.dart';
import 'settings_sub_screen.dart';

/// Settings → Memory & templates. The only two places in this app where
/// anything the user typed can outlive the session.
///
/// Grouped on purpose: both are *opt-in stores on this phone*, both have a
/// delete, and a user who wants to check "what has this app kept about me?"
/// should find the whole answer on one screen rather than between a switch and
/// an About row.
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return SettingsSubScreen(
      title: strings.conversationMemorySection,
      subtitle: strings.settingsMemoryHint,
      children: <Widget>[
        SettingsSection(
          topSpace: AppTheme.spaceSm,
          label: strings.conversationMemorySection,
          child: const ConversationMemoryCard(),
        ),
        SettingsSection(
          label: strings.savedReplies,
          child: const SavedRepliesCard(),
        ),
      ],
    );
  }
}
