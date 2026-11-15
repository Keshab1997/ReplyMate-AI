import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/memory/domain/conversation_memory.dart';
import 'package:replymate/features/reply/data/chat_reply_style_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ConversationKey key(String app, String name) =>
      ConversationKey.tryOf(packageName: app, contactName: name)!;

  test('saves and reloads only the style selected for that chat', () async {
    final store = ChatReplyStyleStore();
    final chat = key('com.whatsapp', 'Asha');
    const style = ChatReplyStyle(
      language: ReplyLanguage.bengali,
      tone: ReplyTone.professional,
      length: ReplyLength.medium,
    );

    await store.save(chat, style);

    expect(await ChatReplyStyleStore().get(chat), style);
    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.key, chat);
    expect(listed.single.style, style);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), contains(AppConstants.prefChatReplyStyles));
  });

  test('a same-named chat in another app has a separate style', () async {
    final store = ChatReplyStyleStore();
    final whatsapp = key('com.whatsapp', 'Asha');
    final telegram = key('org.telegram.messenger', 'Asha');
    const bengali = ChatReplyStyle(
      language: ReplyLanguage.bengali,
      tone: ReplyTone.friendly,
      length: ReplyLength.short,
    );
    const english = ChatReplyStyle(
      language: ReplyLanguage.english,
      tone: ReplyTone.professional,
      length: ReplyLength.long,
    );

    await store.save(whatsapp, bengali);
    await store.save(telegram, english);

    expect(await store.get(whatsapp), bengali);
    expect(await store.get(telegram), english);
    expect(await store.list(), hasLength(2));
  });

  test('updates, removes and clears saved chat styles', () async {
    final store = ChatReplyStyleStore();
    final chat = key('com.whatsapp', 'Asha');
    const first = ChatReplyStyle(
      language: ReplyLanguage.bengali,
      tone: ReplyTone.friendly,
      length: ReplyLength.short,
    );
    const updated = ChatReplyStyle(
      language: ReplyLanguage.hindi,
      tone: ReplyTone.polite,
      length: ReplyLength.long,
    );

    await store.save(chat, first);
    await store.save(chat, updated);
    expect(await store.list(), hasLength(1));
    expect(await store.get(chat), updated);

    await store.remove(chat);
    expect(await store.list(), isEmpty);

    await store.save(chat, first);
    await store.clear();
    expect(await store.get(chat), isNull);
  });

  test(
    'malformed local preference data is treated as no saved style',
    () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefChatReplyStyles: '{not json',
      });
      final store = ChatReplyStyleStore();

      expect(await store.list(), isEmpty);
      expect(await store.get(key('com.whatsapp', 'Asha')), isNull);
    },
  );
}
