import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// The language of the *interface*.
///
/// This is deliberately separate from [ReplyLanguage] (the language a reply is
/// written in): a Bengali speaker talking to an English-speaking colleague
/// wants a Bengali app that drafts English replies. The docs already treat the
/// two as independent settings; this file is where the interface half lives.
enum AppLanguage {
  english('en', 'English'),
  bengali('bn', 'বাংলা');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  static AppLanguage fromCode(String? code) => values.firstWhere(
    (language) => language.code == code,
    orElse: () => AppLanguage.english,
  );
}

/// Every string the redesigned screens show, in one place.
///
/// Deliberately a plain abstract class instead of generated ARB files: the app
/// has two languages and one translator, and a compile error on a missing
/// string is worth more here than a build step. Migrating to `flutter_localizations`
/// later is a mechanical change - the call sites already read from a class.
abstract class AppStrings {
  const AppStrings();

  AppLanguage get language;

  // ---------------------------------------------------------------- shared
  String get appName;
  String get back;
  String get settings;
  String get change;

  // ------------------------------------------------------------------ home
  String get readyTitle;
  String get almostThereTitle;
  String get readySubtitle;
  String get almostThereSubtitle;
  String get listeningTitle;
  String get notListeningTitle;
  String get manage;
  String get enable;
  String get chooseApps;
  String get replyStyleTitle;
  String get generateAReply;
  String get quickStart;
  String get pasteAMessage;
  String get pasteAMessageSubtitle;
  String get supportedApps;
  String get noneSelectedYet;
  String selectedAppsCount(int count);
  String get bubbleTitle;
  String get bubbleShowsOverChats;
  String get bubbleNeedsPermission;
  String get screenReadingTitle;
  String get screenReadingSubtitle;
  String get screenReadingNeedsPermission;
  String get screenReadingDisclosureTitle;
  String get screenReadingDisclosureBody;
  String get screenReadingOpenSettings;
  String get screenReadingBlocked;
  String get connectionTitle;
  String get guestModeUnlessConfigured;

  // ------------------------------------------------------------------ tabs
  String get tabHome;
  String get tabReply;
  String get tabApps;
  String get tabSettings;

  // --------------------------------------------------------------- settings
  String get replyStyle;
  String get languageLabel;
  String get toneLabel;
  String get lengthLabel;
  String get captureSection;
  String get privacySection;
  String get messagesNeverStored;
  String get messagesNeverStoredBody;
  String get nothingSentAlone;
  String get nothingSentAloneBody;
  String get clearLocalPreferences;
  String get appLanguageSection;
  String get appLanguageNote;
}

class EnglishStrings extends AppStrings {
  const EnglishStrings();

  @override
  AppLanguage get language => AppLanguage.english;

  @override
  String get appName => 'ReplyMate';
  @override
  String get back => 'Back';
  @override
  String get settings => 'Settings';
  @override
  String get change => 'Change';

  @override
  String get readyTitle => 'Ready when you are';
  @override
  String get almostThereTitle => 'Almost there';
  @override
  String get readySubtitle => 'It never sends anything by itself.';
  @override
  String get almostThereSubtitle =>
      'Allow notification access to wake the helper up.';
  @override
  String get listeningTitle => 'Listening for messages';
  @override
  String get notListeningTitle => 'Not listening yet';
  @override
  String get manage => 'Manage';
  @override
  String get enable => 'Enable';
  @override
  String get chooseApps => 'Choose apps';
  @override
  String get replyStyleTitle => 'Reply style';
  @override
  String get generateAReply => 'Generate a reply';
  @override
  String get quickStart => 'Quick start';
  @override
  String get pasteAMessage => 'Paste a message';
  @override
  String get pasteAMessageSubtitle => 'Reply to the chat you are in';
  @override
  String get supportedApps => 'Supported apps';
  @override
  String get noneSelectedYet => 'None selected yet';
  @override
  String selectedAppsCount(int count) => '$count selected';
  @override
  String get bubbleTitle => 'Bubble';
  @override
  String get bubbleShowsOverChats => 'Shows over your chats';
  @override
  String get bubbleNeedsPermission => 'Needs a permission';

  @override
  String get screenReadingTitle => 'Read the open chat';

  @override
  String get screenReadingSubtitle =>
      'Drafts a reply from the chat you already have open, where the app '
      'posts no notification.';

  @override
  String get screenReadingNeedsPermission => 'Needs accessibility access';

  @override
  String get screenReadingDisclosureTitle => 'Before you turn this on';

  @override
  String get screenReadingDisclosureBody =>
      'ReplyMate will read the message shown on the screen of the apps you '
      'selected, so it can draft a reply even when no notification appears '
      'because you already have the chat open. It never types into another '
      'app and never sends anything by itself. The text is held in memory '
      'only and is gone when the app closes.';

  @override
  String get screenReadingOpenSettings => 'Open accessibility settings';

  @override
  String get screenReadingBlocked =>
      'Android is not allowing accessibility access for this app, so nothing '
      'is being read.';
  @override
  String get connectionTitle => 'Connection';
  @override
  String get guestModeUnlessConfigured => 'Guest mode unless configured';

  @override
  String get tabHome => 'Home';

  @override
  String get tabReply => 'Reply';

  @override
  String get tabApps => 'Apps';

  @override
  String get tabSettings => 'Settings';

  @override
  String get replyStyle => 'Reply style';
  @override
  String get languageLabel => 'Language';
  @override
  String get toneLabel => 'Tone';
  @override
  String get lengthLabel => 'Length';
  @override
  String get captureSection => 'Capture';
  @override
  String get privacySection => 'Privacy';
  @override
  String get messagesNeverStored => 'Messages are never stored';
  @override
  String get messagesNeverStoredBody =>
      'Nothing you reply to is written to disk or to the logs.';
  @override
  String get nothingSentAlone => 'Nothing is sent by itself';
  @override
  String get nothingSentAloneBody =>
      'ReplyMate drafts. You press the button that sends.';
  @override
  String get clearLocalPreferences => 'Clear local preferences';
  @override
  String get appLanguageSection => 'App language';
  @override
  String get appLanguageNote =>
      'The app speaks Bengali. Replies still follow the reply language above.';
}

class BengaliStrings extends AppStrings {
  const BengaliStrings();

  @override
  AppLanguage get language => AppLanguage.bengali;

  @override
  String get appName => 'ReplyMate';
  @override
  String get back => 'ফিরে যান';
  @override
  String get settings => 'সেটিংস';
  @override
  String get change => 'বদলান';

  @override
  String get readyTitle => 'আমি তৈরি';
  @override
  String get almostThereTitle => 'আর একটু বাকি';
  @override
  String get readySubtitle => 'নিজে থেকে কখনো কিছু পাঠায় না।';
  @override
  String get almostThereSubtitle =>
      'নোটিফিকেশন অ্যাক্সেস দিলে helper জেগে উঠবে।';
  @override
  String get listeningTitle => 'মেসেজের জন্য অপেক্ষায়';
  @override
  String get notListeningTitle => 'এখনো শুনছে না';
  @override
  String get manage => 'দেখুন';
  @override
  String get enable => 'চালু করুন';
  @override
  String get chooseApps => 'অ্যাপ বাছুন';
  @override
  String get replyStyleTitle => 'রিপ্লাইয়ের ধরন';
  @override
  String get generateAReply => 'রিপ্লাই বানাও';
  @override
  String get quickStart => 'দ্রুত শুরু';
  @override
  String get pasteAMessage => 'মেসেজ পেস্ট করুন';
  @override
  String get pasteAMessageSubtitle => 'যে চ্যাটে আছেন তার উত্তর দিন';
  @override
  String get supportedApps => 'যে অ্যাপগুলো চলে';
  @override
  String get noneSelectedYet => 'এখনো কিছু বাছা হয়নি';
  @override
  String selectedAppsCount(int count) => '$countটি বাছা হয়েছে';
  @override
  String get bubbleTitle => 'বাবল';
  @override
  String get bubbleShowsOverChats => 'চ্যাটের উপরে ভাসে';
  @override
  String get bubbleNeedsPermission => 'একটা অনুমতি লাগবে';

  @override
  String get screenReadingTitle => 'খোলা চ্যাট পড়া';

  @override
  String get screenReadingSubtitle =>
      'যে চ্যাট খোলা আছে সেখান থেকেই উত্তর তৈরি করে — ওখানে কোনো '
      'notification আসে না।';

  @override
  String get screenReadingNeedsPermission => 'Accessibility অনুমতি লাগবে';

  @override
  String get screenReadingDisclosureTitle => 'চালু করার আগে';

  @override
  String get screenReadingDisclosureBody =>
      'আপনি যে অ্যাপগুলো বেছে দিয়েছেন, ReplyMate সেগুলোর স্ক্রিনে দেখা '
      'মেসেজটি পড়বে — যাতে চ্যাট খোলা থাকায় notification না এলেও উত্তর '
      'তৈরি করা যায়। এটি অন্য কোনো অ্যাপে নিজে থেকে কিছু লিখবে না, নিজে '
      'থেকে কিছু পাঠাবে না। টেক্সট শুধু মেমোরিতে থাকে, অ্যাপ বন্ধ হলে '
      'মুছে যায়।';

  @override
  String get screenReadingOpenSettings => 'Accessibility সেটিংস খুলুন';

  @override
  String get screenReadingBlocked =>
      'Android এই অ্যাপকে accessibility অনুমতি দিচ্ছে না, তাই কিছুই '
      'পড়া হচ্ছে না।';
  @override
  String get connectionTitle => 'সংযোগ';
  @override
  String get guestModeUnlessConfigured => 'কনফিগার না করলে গেস্ট মোড';

  @override
  String get tabHome => 'হোম';

  @override
  String get tabReply => 'উত্তর';

  @override
  String get tabApps => 'অ্যাপ';

  @override
  String get tabSettings => 'সেটিংস';

  @override
  String get replyStyle => 'রিপ্লাইয়ের ধরন';
  @override
  String get languageLabel => 'ভাষা';
  @override
  String get toneLabel => 'সুর';
  @override
  String get lengthLabel => 'দৈর্ঘ্য';
  @override
  String get captureSection => 'ক্যাপচার';
  @override
  String get privacySection => 'প্রাইভেসি';
  @override
  String get messagesNeverStored => 'মেসেজ কোথাও জমা থাকে না';
  @override
  String get messagesNeverStoredBody =>
      'আপনি যে মেসেজের উত্তর দেন, তা ডিস্কে বা লগে লেখা হয় না।';
  @override
  String get nothingSentAlone => 'নিজে থেকে কিছু পাঠায় না';
  @override
  String get nothingSentAloneBody =>
      'ReplyMate শুধু খসড়া বানায়। পাঠানোর বোতাম আপনি চাপবেন।';
  @override
  String get clearLocalPreferences => 'লোকাল পছন্দ মুছে ফেলুন';
  @override
  String get appLanguageSection => 'অ্যাপের ভাষা';
  @override
  String get appLanguageNote =>
      'অ্যাপ বাংলায় চলবে। রিপ্লাই কিন্তু উপরের ভাষা অনুযায়ীই তৈরি হবে।';
}

final NotifierProvider<AppLanguageNotifier, AppLanguage> appLanguageProvider =
    NotifierProvider<AppLanguageNotifier, AppLanguage>(AppLanguageNotifier.new);

class AppLanguageNotifier extends Notifier<AppLanguage> {
  bool _alive = true;

  @override
  AppLanguage build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return AppLanguage.english;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_alive) return;
    state = AppLanguage.fromCode(prefs.getString(AppConstants.prefAppLanguage));
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefAppLanguage, language.code);
  }
}

/// The strings for the current interface language.
final Provider<AppStrings> appStringsProvider = Provider<AppStrings>((ref) {
  final language = ref.watch(appLanguageProvider);
  return switch (language) {
    AppLanguage.english => const EnglishStrings(),
    AppLanguage.bengali => const BengaliStrings(),
  };
});
