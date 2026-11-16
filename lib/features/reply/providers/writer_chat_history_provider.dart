import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../memory/providers/conversation_memory_provider.dart';
import '../data/writer_chat_history_store.dart';

final writerChatHistoryProvider = FutureProvider<List<WriterChatHistory>>((
  ref,
) async {
  final enabled = ref.watch(conversationMemoryEnabledProvider);
  await ref.read(conversationMemoryEnabledProvider.notifier).ready;
  if (!enabled || !ref.read(conversationMemoryEnabledProvider)) {
    return const <WriterChatHistory>[];
  }
  return ref.watch(writerChatHistoryStoreProvider).all();
});
