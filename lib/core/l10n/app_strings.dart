import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// The language of the *interface*.
/// This is deliberately separate from [ReplyLanguage] (the language a reply is
/// written in): a Bengali speaker talking to an English-speaking colleague
/// wants a Bengali app that drafts English replies. The docs already treat the
/// two as independent settings; this file is where the interface half lives.
enum AppLanguage {
  english('en', 'English'),
  bengali('bn', 'বাংলা'),
  hindi('hi', 'हिन्दी');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  static AppLanguage fromCode(String? code) => values.firstWhere(
    (language) => language.code == code,
    orElse: () => AppLanguage.english,
  );
}

/// Every string the redesigned screens show, in one place.
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

  // ------------------------------------------------ bubble, composer, memory
  String get suggestionOne;
  String get suggestionMany;
  String get messageCopied;
  String get clipboardEmpty;
  String get replyCopied;
  String get shareOpened;
  String get shareUnavailable;
  String get nothingToReplyTo;
  String get close;
  String get messageGoneBody;
  String get pasteHint;
  String get noTextInNotification;
  String get paste;
  String get aiNotConfiguredPanel;
  String get generating;
  String get generateSuggestions;
  String get noMessageCaptured;
  String get newReply;
  String get messageLabel;
  String get clear;
  String get messageTextHint;
  String get howManyOptions;
  String get sentOnlyOnGenerate;
  String get oneWayToSayIt;
  String get noTextVisible;
  String get generateAgain;
  String get bestFit;
  String get share;
  String get conversationMemorySection;
  String get bubbleSwitchTitle;
  String get refresh;
  String get rememberRecentChats;
  String get rememberRecentChatsBody;
  String get nothingRememberedYet;
  String get forgetThisChat;
  String get deleteAllRemembered;
  String get deleteAllTitle;
  String get deleteAllBody;
  String get keep;
  String get delete;
  String suggestionsLabel(int count);
  String generateSuggestionsCount(int count);
  String fromSource(String source);
  String forgotConversation(String name);

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
  String get messagesNeverStored => 'Messages are not stored by default';
  @override
  String get messagesNeverStoredBody =>
      'Nothing you reply to is written to disk or to the logs. The one '
      'exception is "Remember recent chats" - off unless you turn it on, kept '
      'on this device only, capped at 40 lines per chat for 7 days, and deleted '
      'when you switch it off.';
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
  String get suggestionOne => 'Suggestion';
  @override
  String get suggestionMany => 'Suggestions';
  @override
  String get messageCopied => 'Message copied. Paste it anywhere.';
  @override
  String get clipboardEmpty => 'The clipboard is empty.';
  @override
  String get replyCopied => 'Reply copied.';
  @override
  String get shareOpened => 'Share sheet opened. Choose an app to continue.';
  @override
  String get shareUnavailable =>
      'Sharing is unavailable here. Copy the reply instead.';
  @override
  String get nothingToReplyTo => 'Nothing to reply to';
  @override
  String get close => 'Close';
  @override
  String get messageGoneBody =>
      'This message is no longer available. ReplyMate keeps a message only in memory, so it is gone once the panel closes or the app is stopped. Wait for the next message, or paste the text in the composer.';
  @override
  String get pasteHint => 'Paste the message you want to reply to';
  @override
  String get noTextInNotification =>
      'This notification exposed no message text. Use Paste below to reply to something yourself.';
  @override
  String get paste => 'Paste';
  @override
  String get aiNotConfiguredPanel =>
      'AI generation is not configured on this install, so generating will explain that instead of inventing a reply.';
  @override
  String get generating => 'Generating…';
  @override
  String get generateSuggestions => 'Generate suggestions';
  @override
  String get noMessageCaptured =>
      'No message was captured. ReplyMate only keeps a message while the app is open, so paste the text below to reply to something yourself.';
  @override
  String get newReply => 'New reply';
  @override
  String get messageLabel => 'MESSAGE';
  @override
  String get clear => 'Clear';
  @override
  String get messageTextHint => 'Message text…';
  @override
  String get howManyOptions => 'How many options';
  @override
  String get sentOnlyOnGenerate =>
      'The message is sent to an AI service only when you press Generate.';
  @override
  String get oneWayToSayIt => 'One way to say it';
  @override
  String get noTextVisible =>
      'No message text was visible in the notification.';
  @override
  String get generateAgain => 'Generate again';
  @override
  String get bestFit => 'BEST FIT';
  @override
  String get share => 'Share';
  @override
  String get conversationMemorySection => 'Conversation memory';
  @override
  String get bubbleSwitchTitle => 'Floating reply bubble';
  @override
  String get refresh => 'Refresh';
  @override
  String get rememberRecentChats => 'Remember recent chats';
  @override
  String get rememberRecentChatsBody =>
      'Keeps the last few messages of each chat - and replies you accept - so the next draft follows the conversation and sounds like you. Stored on this device only, never uploaded, and never in a backup. Off by default; turning it off deletes everything it kept.';
  @override
  String get nothingRememberedYet =>
      'Nothing remembered yet. Open a reply for a chat and it will show up here.';
  @override
  String get forgetThisChat => 'Forget this chat';
  @override
  String get deleteAllRemembered => 'Delete all remembered chats';
  @override
  String get deleteAllTitle => 'Delete all remembered chats?';
  @override
  String get deleteAllBody =>
      'Every message this app remembered is deleted from this device. The replies are not affected - only what the app kept to write them.';
  @override
  String get keep => 'Keep';
  @override
  String get delete => 'Delete';
  @override
  String suggestionsLabel(int count) =>
      count == 1 ? suggestionOne : suggestionMany;
  @override
  String generateSuggestionsCount(int count) => 'Generate $count suggestions';
  @override
  String fromSource(String source) => 'From $source.';
  @override
  String forgotConversation(String name) =>
      'Forgot the conversation with $name.';
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
  String get messagesNeverStored => 'মেসেজ ডিফল্টভাবে কোথাও জমা থাকে না';
  @override
  String get messagesNeverStoredBody =>
      'আপনি যে মেসেজের উত্তর দেন, তা ডিস্কে বা লগে লেখা হয় না। একমাত্র '
      'ব্যতিক্রম "সাম্প্রতিক চ্যাট মনে রাখা" - আপনি চালু না করলে বন্ধ, শুধু এই '
      'ডিভাইসে, প্রতি চ্যাটে ৪০ লাইন ৭ দিন, আর বন্ধ করলেই মুছে যায়।';
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
  String get suggestionOne => 'পরামর্শ';
  @override
  String get suggestionMany => 'পরামর্শগুলো';
  @override
  String get messageCopied => 'মেসেজ কপি হয়েছে। যেখানে খুশি পেস্ট করুন।';
  @override
  String get clipboardEmpty => 'ক্লিপবোর্ড খালি।';
  @override
  String get replyCopied => 'জবাব কপি হয়েছে।';
  @override
  String get shareOpened => 'শেয়ার শিট খুলেছে। কোন অ্যাপে পাঠাবেন বেছে নিন।';
  @override
  String get shareUnavailable =>
      'এখানে শেয়ার করা যাচ্ছে না। জবাবটি কপি করে নিন।';
  @override
  String get nothingToReplyTo => 'উত্তর দেওয়ার মতো কিছু নেই';
  @override
  String get close => 'বন্ধ করুন';
  @override
  String get messageGoneBody =>
      'এই মেসেজটি আর নেই। ReplyMate মেসেজ শুধু মেমোরিতে রাখে, তাই প্যানেল বন্ধ হলে বা অ্যাপ বন্ধ হলে তা চলে যায়। পরের মেসেজের জন্য অপেক্ষা করুন, বা কম্পোজারে টেক্সট পেস্ট করুন।';
  @override
  String get pasteHint => 'যে মেসেজের উত্তর চান সেটি পেস্ট করুন';
  @override
  String get noTextInNotification =>
      'এই নোটিফিকেশনে কোনো মেসেজ টেক্সট ছিল না। নিচের Paste দিয়ে নিজে কিছু লিখে উত্তর দিন।';
  @override
  String get paste => 'পেস্ট';
  @override
  String get aiNotConfiguredPanel =>
      'এই ইনস্টলে AI চালু নেই, তাই জেনারেট করলে ভুয়া জবাব না দিয়ে সেটাই জানাবে।';
  @override
  String get generating => 'তৈরি হচ্ছে…';
  @override
  String get generateSuggestions => 'পরামর্শ তৈরি করুন';
  @override
  String get noMessageCaptured =>
      'কোনো মেসেজ ধরা পড়েনি। ReplyMate মেসেজ রাখে শুধু অ্যাপ খোলা থাকা পর্যন্ত, তাই নিচে টেক্সট পেস্ট করে নিজে উত্তর দিন।';
  @override
  String get newReply => 'নতুন জবাব';
  @override
  String get messageLabel => 'মেসেজ';
  @override
  String get clear => 'মুছুন';
  @override
  String get messageTextHint => 'মেসেজের টেক্সট…';
  @override
  String get howManyOptions => 'কতগুলো অপশন';
  @override
  String get sentOnlyOnGenerate =>
      'আপনি Generate চাপলে তবেই মেসেজটি AI সার্ভিসে যায়।';
  @override
  String get oneWayToSayIt => 'বলার একটি উপায়';
  @override
  String get noTextVisible => 'নোটিফিকেশনে কোনো মেসেজ টেক্সট দেখা যায়নি।';
  @override
  String get generateAgain => 'আবার তৈরি করুন';
  @override
  String get bestFit => 'সবচেয়ে মানানসই';
  @override
  String get share => 'শেয়ার';
  @override
  String get conversationMemorySection => 'কথোপকথনের স্মৃতি';
  @override
  String get bubbleSwitchTitle => 'ভাসমান রিপ্লাই বাবল';
  @override
  String get refresh => 'রিফ্রেশ';
  @override
  String get rememberRecentChats => 'সাম্প্রতিক চ্যাট মনে রাখুন';
  @override
  String get rememberRecentChatsBody =>
      'প্রতি চ্যাটের শেষ কয়েকটি মেসেজ - আর আপনি যে জবাবগুলো নেন - মনে রাখে, যাতে পরের ড্রাফট কথোপকথন ধরে আর আপনার মতো শোনায়। শুধু এই ডিভাইসে রাখা হয়, কোথাও আপলোড হয় না, ব্যাকআপেও যায় না। ডিফল্টভাবে বন্ধ; বন্ধ করলে সব মুছে যায়।';
  @override
  String get nothingRememberedYet =>
      'এখনো কিছু মনে রাখা হয়নি। কোনো চ্যাটের জবাব খুললে সেটি এখানে দেখা যাবে।';
  @override
  String get forgetThisChat => 'এই চ্যাট ভুলে যান';
  @override
  String get deleteAllRemembered => 'মনে রাখা সব চ্যাট মুছুন';
  @override
  String get deleteAllTitle => 'মনে রাখা সব চ্যাট মুছবেন?';
  @override
  String get deleteAllBody =>
      'এই অ্যাপের মনে রাখা প্রতিটি মেসেজ এই ডিভাইস থেকে মুছে যাবে। জবাবগুলোতে কিছু হয় না - শুধু যেসব কথা অ্যাপটি জবাব লেখার জন্য রেখেছিল।';
  @override
  String get keep => 'রাখুন';
  @override
  String get delete => 'মুছুন';
  @override
  String suggestionsLabel(int count) =>
      count == 1 ? suggestionOne : suggestionMany;
  @override
  String generateSuggestionsCount(int count) => '$countটি পরামর্শ তৈরি করুন';
  @override
  String fromSource(String source) => '$source থেকে।';
  @override
  String forgotConversation(String name) => '$name-এর সঙ্গে কথোপকথন ভুলে গেছি।';
  @override
  String get appLanguageNote =>
      'অ্যাপ বাংলায় চলবে। রিপ্লাই কিন্তু উপরের ভাষা অনুযায়ীই তৈরি হবে।';
}

final NotifierProvider<AppLanguageNotifier, AppLanguage> appLanguageProvider =
    NotifierProvider<AppLanguageNotifier, AppLanguage>(AppLanguageNotifier.new);

/// Hindi. The third interface language, and the one where the words have to be
/// checked by a speaker rather than by a compiler - `hi` here means the
/// interface only, exactly like `bn` (see [ReplyLanguage] for the reply).
class HindiStrings extends AppStrings {
  const HindiStrings();

  @override
  AppLanguage get language => AppLanguage.hindi;

  @override
  String get appName => 'ReplyMate';
  @override
  String get back => 'पीछे';
  @override
  String get settings => 'सेटिंग्स';
  @override
  String get change => 'बदलें';

  @override
  String get readyTitle => 'जब आप तैयार हों';
  @override
  String get almostThereTitle => 'बस थोड़ा सा बाकी';
  @override
  String get readySubtitle => 'यह कभी अपने आप कुछ नहीं भेजता।';
  @override
  String get almostThereSubtitle =>
      'सहायक को जगाने के लिए नोटिफिकेशन की अनुमति दें।';
  @override
  String get listeningTitle => 'संदेशों पर नज़र';
  @override
  String get notListeningTitle => 'अभी सुन नहीं रहा';
  @override
  String get manage => 'प्रबंधित करें';
  @override
  String get enable => 'चालू करें';
  @override
  String get chooseApps => 'ऐप चुनें';
  @override
  String get replyStyleTitle => 'जवाब की शैली';
  @override
  String get generateAReply => 'जवाब बनाएँ';
  @override
  String get quickStart => 'तुरंत शुरू करें';
  @override
  String get pasteAMessage => 'संदेश पेस्ट करें';
  @override
  String get pasteAMessageSubtitle => 'जिस चैट में हैं उसका जवाब दें';
  @override
  String get supportedApps => 'समर्थित ऐप';
  @override
  String get noneSelectedYet => 'अभी कुछ नहीं चुना';
  @override
  String selectedAppsCount(int count) => '$count चुने गए';
  @override
  String get bubbleTitle => 'बबल';
  @override
  String get bubbleShowsOverChats => 'आपकी चैट के ऊपर दिखता है';
  @override
  String get bubbleNeedsPermission => 'अनुमति चाहिए';

  @override
  String get screenReadingTitle => 'खुली चैट पढ़ें';

  @override
  String get screenReadingSubtitle =>
      'जो चैट आपने पहले से खोली हुई है, उसी से जवाब तैयार करता है - जहाँ ऐप कोई '
      'नोटिफिकेशन नहीं भेजता।';

  @override
  String get screenReadingNeedsPermission => 'एक्सेसिबिलिटी अनुमति चाहिए';

  @override
  String get screenReadingDisclosureTitle => 'इसे चालू करने से पहले';

  @override
  String get screenReadingDisclosureBody =>
      'ReplyMate आपके चुने हुए ऐप की स्क्रीन पर दिख रहा संदेश पढ़ेगा, ताकि जब '
      'चैट पहले से खुली होने के कारण कोई नोटिफिकेशन न आए तब भी जवाब तैयार हो '
      'सके। यह किसी दूसरे ऐप में कभी टाइप नहीं करता और अपने आप कुछ नहीं भेजता। '
      'पाठ केवल मेमोरी में रहता है और ऐप बंद होते ही चला जाता है।';

  @override
  String get screenReadingOpenSettings => 'एक्सेसिबिलिटी सेटिंग्स खोलें';

  @override
  String get screenReadingBlocked =>
      'Android इस ऐप को एक्सेसिबिलिटी अनुमति नहीं दे रहा, इसलिए कुछ भी नहीं पढ़ा '
      'जा रहा।';
  @override
  String get connectionTitle => 'कनेक्शन';
  @override
  String get guestModeUnlessConfigured => 'कॉन्फ़िगर न होने पर गेस्ट मोड';

  @override
  String get tabHome => 'होम';

  @override
  String get tabReply => 'जवाब';

  @override
  String get tabApps => 'ऐप';

  @override
  String get tabSettings => 'सेटिंग्स';

  @override
  String get replyStyle => 'जवाब की शैली';
  @override
  String get languageLabel => 'भाषा';
  @override
  String get toneLabel => 'लहज़ा';
  @override
  String get lengthLabel => 'लंबाई';
  @override
  String get captureSection => 'कैप्चर';
  @override
  String get privacySection => 'निजता';
  @override
  String get messagesNeverStored => 'संदेश डिफ़ॉल्ट रूप से कहीं जमा नहीं होते';
  @override
  String get messagesNeverStoredBody =>
      'आप जिस संदेश का जवाब देते हैं, वह डिस्क या लॉग में नहीं लिखा जाता। एकमात्र '
      'अपवाद "हाल की चैट याद रखें" है - आपके चालू किए बिना बंद, केवल इसी डिवाइस '
      'पर, हर चैट में 40 लाइनें 7 दिन तक, और बंद करते ही मिट जाता है।';
  @override
  String get nothingSentAlone => 'कुछ भी अपने आप नहीं भेजा जाता';
  @override
  String get nothingSentAloneBody =>
      'ReplyMate जवाब लिखता है। भेजने का बटन आप दबाते हैं।';
  @override
  String get clearLocalPreferences => 'लोकल प्राथमिकताएँ साफ़ करें';
  @override
  String get appLanguageSection => 'ऐप की भाषा';
  @override
  String get suggestionOne => 'सुझाव';
  @override
  String get suggestionMany => 'सुझाव';
  @override
  String get messageCopied => 'संदेश कॉपी हो गया। जहाँ चाहें पेस्ट करें।';
  @override
  String get clipboardEmpty => 'क्लिपबोर्ड खाली है।';
  @override
  String get replyCopied => 'जवाब कॉपी हो गया।';
  @override
  String get shareOpened => 'शेयर शीट खुल गई। जारी रखने के लिए ऐप चुनें।';
  @override
  String get shareUnavailable => 'यहाँ शेयर उपलब्ध नहीं है। जवाब कॉपी कर लें।';
  @override
  String get nothingToReplyTo => 'जवाब देने के लिए कुछ नहीं';
  @override
  String get close => 'बंद करें';
  @override
  String get messageGoneBody =>
      'यह संदेश अब उपलब्ध नहीं है। ReplyMate संदेश केवल मेमोरी में रखता है, इसलिए पैनल बंद होते ही या ऐप रुकते ही वह चला जाता है। अगले संदेश का इंतज़ार करें, या कंपोज़र में पाठ पेस्ट करें।';
  @override
  String get pasteHint => 'जिस संदेश का जवाब चाहिए उसे पेस्ट करें';
  @override
  String get noTextInNotification =>
      'इस नोटिफिकेशन में कोई संदेश पाठ नहीं था। नीचे Paste से खुद कुछ लिखकर जवाब दें।';
  @override
  String get paste => 'पेस्ट';
  @override
  String get aiNotConfiguredPanel =>
      'इस इंस्टॉल पर AI कॉन्फ़िगर नहीं है, इसलिए जनरेट करने पर नकली जवाब के बजाय यही बताया जाएगा।';
  @override
  String get generating => 'बन रहा है…';
  @override
  String get generateSuggestions => 'सुझाव बनाएँ';
  @override
  String get noMessageCaptured =>
      'कोई संदेश कैप्चर नहीं हुआ। ReplyMate संदेश केवल ऐप खुला रहने तक रखता है, इसलिए नीचे पाठ पेस्ट करके खुद जवाब दें।';
  @override
  String get newReply => 'नया जवाब';
  @override
  String get messageLabel => 'संदेश';
  @override
  String get clear => 'हटाएँ';
  @override
  String get messageTextHint => 'संदेश का पाठ…';
  @override
  String get howManyOptions => 'कितने विकल्प';
  @override
  String get sentOnlyOnGenerate =>
      'संदेश AI सेवा को केवल तब भेजा जाता है जब आप Generate दबाते हैं।';
  @override
  String get oneWayToSayIt => 'कहने का एक तरीका';
  @override
  String get noTextVisible => 'नोटिफिकेशन में कोई संदेश पाठ दिखाई नहीं दिया।';
  @override
  String get generateAgain => 'फिर बनाएँ';
  @override
  String get bestFit => 'सबसे उपयुक्त';
  @override
  String get share => 'शेयर';
  @override
  String get conversationMemorySection => 'बातचीत की याद';
  @override
  String get bubbleSwitchTitle => 'फ़्लोटिंग रिप्लाई बबल';
  @override
  String get refresh => 'रीफ़्रेश';
  @override
  String get rememberRecentChats => 'हाल की चैट याद रखें';
  @override
  String get rememberRecentChatsBody =>
      'हर चैट के पिछले कुछ संदेश - और आपके स्वीकार किए जवाब - याद रखता है, ताकि अगला ड्राफ़्ट बातचीत को आगे बढ़ाए और आप जैसा लगे। केवल इसी डिवाइस पर, कहीं अपलोड नहीं, बैकअप में भी नहीं। डिफ़ॉल्ट रूप से बंद; बंद करने पर सब मिट जाता है।';
  @override
  String get nothingRememberedYet =>
      'अभी कुछ याद नहीं रखा गया। किसी चैट का जवाब खोलें, वह यहाँ दिखेगा।';
  @override
  String get forgetThisChat => 'यह चैट भुला दें';
  @override
  String get deleteAllRemembered => 'याद रखी सभी चैट हटाएँ';
  @override
  String get deleteAllTitle => 'याद रखी सभी चैट हटाएँ?';
  @override
  String get deleteAllBody =>
      'इस ऐप ने जो भी संदेश याद रखा था, वह इस डिवाइस से हट जाएगा। जवाबों पर कोई असर नहीं - केवल वही मिटेगा जो जवाब लिखने के लिए रखा गया था।';
  @override
  String get keep => 'रखें';
  @override
  String get delete => 'हटाएँ';
  @override
  String suggestionsLabel(int count) =>
      count == 1 ? suggestionOne : suggestionMany;
  @override
  String generateSuggestionsCount(int count) => '$count सुझाव बनाएँ';
  @override
  String fromSource(String source) => '$source से।';
  @override
  String forgotConversation(String name) => '$name के साथ बातचीत भुला दी गई।';
  @override
  String get appLanguageNote =>
      'ऐप हिंदी में चलेगा। जवाब फिर भी ऊपर चुनी गई जवाब की भाषा में बनेंगे।';
}

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
    AppLanguage.hindi => const HindiStrings(),
  };
});
