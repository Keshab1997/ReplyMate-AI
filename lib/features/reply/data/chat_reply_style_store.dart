import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/reply_options.dart';
import '../../memory/domain/conversation_memory.dart';

/// Reply style the user explicitly chose to reuse for one chat.
/// It deliberately contains no message content or inferred relationship data.
class ChatReplyStyle {
  const ChatReplyStyle({
    required this.language,
    required this.tone,
    required this.length,
  });

  final ReplyLanguage language;
  final ReplyTone tone;
  final ReplyLength length;

  Map<String, Object?> toJson() => {
    'language': language.code,
    'tone': tone.name,
    'length': length.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatReplyStyle &&
      other.language == language &&
      other.tone == tone &&
      other.length == length;

  @override
  int get hashCode => Object.hash(language, tone, length);

  static ChatReplyStyle? fromJson(Map<Object?, Object?> json) {
    final languageCode = json['language'];
    final toneName = json['tone'];
    final lengthName = json['length'];
    if (languageCode is! String ||
        toneName is! String ||
        lengthName is! String) {
      return null;
    }
    final language = ReplyLanguage.values.where(
      (value) => value.code == languageCode,
    );
    final tone = ReplyTone.values.where((value) => value.name == toneName);
    final length = ReplyLength.values.where(
      (value) => value.name == lengthName,
    );
    if (language.isEmpty || tone.isEmpty || length.isEmpty) return null;
    return ChatReplyStyle(
      language: language.first,
      tone: tone.first,
      length: length.first,
    );
  }
}

class ChatReplyStyleEntry {
  const ChatReplyStyleEntry({required this.key, required this.style});

  final ConversationKey key;
  final ChatReplyStyle style;
}

/// Local-only persistence for explicit per-chat reply styles.
/// The key reuses the app's documented package + notification display-name
/// identity. No phone Contacts permission is requested; if the name changes,
/// or two chats share a name in one app, the match can be imperfect.
class ChatReplyStyleStore {
  Future<List<ChatReplyStyleEntry>> list() async {
    final entries = await _read();
    return entries.values.toList(growable: false);
  }

  Future<ChatReplyStyle?> get(ConversationKey key) async =>
      (await _read())[key.id]?.style;

  Future<void> save(ConversationKey key, ChatReplyStyle style) async {
    final entries = await _read();
    entries[key.id] = ChatReplyStyleEntry(key: key, style: style);
    await _write(entries);
  }

  Future<void> remove(ConversationKey key) async {
    final entries = await _read();
    entries.remove(key.id);
    await _write(entries);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefChatReplyStyles);
  }

  Future<Map<String, ChatReplyStyleEntry>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The floating panel runs in another Flutter engine; reload before each
      // read so Settings sees styles saved there after the app resumes.
      await prefs.reload();
      final raw = prefs.getString(AppConstants.prefChatReplyStyles);
      if (raw == null || raw.isEmpty) return <String, ChatReplyStyleEntry>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String, ChatReplyStyleEntry>{};
      final result = <String, ChatReplyStyleEntry>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<Object?, Object?>.from(item);
        final packageName = map['packageName'];
        final contactName = map['contactName'];
        final rawStyle = map['style'];
        if (packageName is! String ||
            contactName is! String ||
            rawStyle is! Map) {
          continue;
        }
        final key = ConversationKey.tryOf(
          packageName: packageName,
          contactName: contactName,
        );
        final style = ChatReplyStyle.fromJson(
          Map<Object?, Object?>.from(rawStyle),
        );
        if (key == null || style == null) continue;
        result[key.id] = ChatReplyStyleEntry(key: key, style: style);
      }
      return result;
    } catch (_) {
      // A preference read failure is the same as having no saved style; it
      // must never prevent a draft from being generated.
      return <String, ChatReplyStyleEntry>{};
    }
  }

  Future<void> _write(Map<String, ChatReplyStyleEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.prefChatReplyStyles,
      jsonEncode([
        for (final entry in entries.values)
          {
            'packageName': entry.key.packageName,
            'contactName': entry.key.contactName,
            'style': entry.style.toJson(),
          },
      ]),
    );
  }
}

final Provider<ChatReplyStyleStore> chatReplyStyleStoreProvider =
    Provider<ChatReplyStyleStore>((ref) => ChatReplyStyleStore());

final FutureProvider<List<ChatReplyStyleEntry>> chatReplyStylesProvider =
    FutureProvider<List<ChatReplyStyleEntry>>(
      (ref) => ref.watch(chatReplyStyleStoreProvider).list(),
    );
