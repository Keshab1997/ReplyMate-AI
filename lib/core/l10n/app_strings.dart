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

  // ------------------------------------------------- setup path: onboarding,
  // permissions, app selection, screen reading.
  //
  // One block rather than sprinkled per screen: these were the strings still
  // rendered as literal English inside a Bengali session, so keeping them
  // adjacent makes "is the setup path localised?" answerable in one place.
  String get onboardingBadge;
  String get onboardingTitle;
  String get onboardingSubtitle;
  String get onboardingPointConsentTitle;
  String get onboardingPointConsentBody;
  String get onboardingPointNotificationsTitle;
  String get onboardingPointNotificationsBody;
  String get onboardingPointLanguagesTitle;
  String get onboardingPointLanguagesBody;
  String get onboardingPointPrivacyTitle;
  String get onboardingPointPrivacyBody;
  String get onboardingGetStarted;
  String get onboardingFooter;
  String get permissionTitle;
  String get permissionGranted;
  String get permissionNeeded;
  String get permissionWhatAllows;
  String get permissionAllowsTitle;
  String get permissionAllowsBody;
  String get permissionNoReadTitle;
  String get permissionNoReadBody;
  String get permissionOpenSettings;
  String get permissionLater;
  String get permissionOptionalBubble;
  String get permissionOverlayGranted;
  String get permissionOverlayNotGranted;
  String get permissionOverlayBody;
  String get permissionOverlayNotDoTitle;
  String get permissionOverlayNotDoBody;
  String get permissionOverlayAndroid13;
  String get permissionOpenOverlay;
  String get permissionManageOverlay;
  String get appsTitle;
  String get appsNothingYet;
  String appsSelectedOf(int selected, int total);
  String get appsNoneInstalledTitle;
  String get appsNoneInstalledBody;
  String get appsReadFrom;
  String get appsNotificationsOnly;
  String get appsWhyListed;
  String get appsReadFailed;
  String get readerTitle;
  String get readerWhatDoing;
  String get readerRefresh;
  String get readerOpenSettings;
  String get readerNoAccessibility;
  String get readerNoAnswer;
  String get readerServiceStopped;
  String get readerSwitchOff;
  String get readerWatchingNothing;
  String readerWatching(String apps);
  String readerScans(int count);
  String readerLastScan(String summary);
  String get readerNothingYet;
  String readerSeen(String text);
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
  // ------------------------------------------------------- setup path

  @override
  String get onboardingBadge => 'YOUR AI REPLY ASSISTANT';

  @override
  String get onboardingTitle => 'ReplyMate AI';

  @override
  String get onboardingSubtitle =>
      'Thoughtful replies in your language,\\nwith you always in control.';

  @override
  String get onboardingPointConsentTitle => 'Replies you approve, always';

  @override
  String get onboardingPointConsentBody =>
      'ReplyMate suggests replies. You review, edit and send - the app never sends anything on its own.';

  @override
  String get onboardingPointNotificationsTitle => 'Works from notifications';

  @override
  String get onboardingPointNotificationsBody =>
      'With your permission it reads notifications from apps you select. Some apps hide or shorten notification text; when that happens ReplyMate says so instead of guessing.';

  @override
  String get onboardingPointLanguagesTitle => 'Bengali, Hindi and English';

  @override
  String get onboardingPointLanguagesBody =>
      'Pick the language and tone for every reply - friendly, casual, professional, polite, funny or short.';

  @override
  String get onboardingPointPrivacyTitle => 'Privacy first';

  @override
  String get onboardingPointPrivacyBody =>
      'Message text is sent to an AI service only when you ask for a reply, and nothing is stored on this device.';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingFooter => 'You choose what ReplyMate can access.';

  @override
  String get permissionTitle => 'Notification access';

  @override
  String get permissionGranted => 'Granted';

  @override
  String get permissionNeeded => 'Needed for the bubble';

  @override
  String get permissionWhatAllows => 'What this access allows';

  @override
  String get permissionAllowsTitle => 'Notifications from apps you pick';

  @override
  String get permissionAllowsBody =>
      'ReplyMate processes only the apps you select on the next screen, uses the text solely to draft replies, and never stores conversations.';

  @override
  String get permissionNoReadTitle => 'No reading inside apps';

  @override
  String get permissionNoReadBody =>
      'No screen capture, no accessibility service, no sending messages. You can revoke the access here or in Android Settings at any time.';

  @override
  String get permissionOpenSettings => 'Open Android Settings';

  @override
  String get permissionLater => 'Later - I will paste text manually';

  @override
  String get permissionOptionalBubble => 'OPTIONAL · FLOATING REPLY BUBBLE';

  @override
  String get permissionOverlayGranted => 'Overlay access granted';

  @override
  String get permissionOverlayNotGranted => 'Overlay access not granted';

  @override
  String get permissionOverlayBody =>
      'A small ReplyMate bubble can float over the app you are in when a '
      'message arrives from an app you selected. Tapping it opens a panel to '
      'draft a reply without leaving the conversation. It is optional, and off '
      'by default.';

  @override
  String get permissionOverlayNotDoTitle => 'What it does not do';

  @override
  String get permissionOverlayNotDoBody =>
      'It never reads the screen, the app underneath, or anything another app '
      'displays. It only knows what the notification already posted. It never '
      'sends a message by itself, and it keeps no message after the panel '
      'closes.';

  @override
  String get permissionOverlayAndroid13 =>
      'On Android 13 and later, notifications must also be allowed, so the '
      'bubble can show its own silent notification and the fallback "New '
      'message from …" notification can appear.';

  @override
  String get permissionOpenOverlay => 'Open "Display over other apps"';

  @override
  String get permissionManageOverlay => 'Manage overlay access';

  @override
  String get appsTitle => 'Supported apps';

  @override
  String get appsNothingYet => 'Nothing to choose yet';

  @override
  String appsSelectedOf(int selected, int total) =>
      '$selected of $total selected';

  @override
  String get appsNoneInstalledTitle =>
      'No supported messaging app is installed on this device.';

  @override
  String get appsNoneInstalledBody =>
      'You can still use ReplyMate by pasting or selecting text.';

  @override
  String get appsReadFrom => 'APPS REPLYMATE MAY READ NOTIFICATIONS FROM';

  @override
  String get appsNotificationsOnly =>
      'Notifications only - never inside the app';

  @override
  String get appsWhyListed =>
      'An app appears here only after it has been seen installed on this '
      'device. Support is claimed only for what has been tested.';

  @override
  String get appsReadFailed => 'Could not read the installed app list.';

  @override
  String get readerTitle => 'Screen reading';

  @override
  String get readerWhatDoing => 'What the reader is doing';

  @override
  String get readerRefresh => 'Refresh';

  @override
  String get readerOpenSettings => 'Open Android settings';

  @override
  String get readerNoAccessibility =>
      'This phone has no accessibility screen to open. Look for it under Settings → Accessibility.';

  @override
  String get readerNoAnswer => 'No answer from the native side yet.';

  @override
  String get readerServiceStopped => 'Service: not running';

  @override
  String get readerSwitchOff => 'Switch: off';

  @override
  String get readerWatchingNothing => 'Watching: nothing selected';

  @override
  String readerWatching(String apps) => 'Watching: $apps';

  @override
  String readerScans(int count) => 'Scans: $count';

  @override
  String readerLastScan(String summary) => 'Last scan: $summary';

  @override
  String get readerNothingYet =>
      'Nothing to read yet - open a chat in a watched app.';

  @override
  String readerSeen(String text) => 'Seen: "$text"';
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
  // ------------------------------------------------------- setup path

  @override
  String get onboardingBadge => 'আপনার এআই রিপ্লাই সহায়ক';

  @override
  String get onboardingTitle => 'ReplyMate AI';

  @override
  String get onboardingSubtitle =>
      'আপনার ভাষায় ভেবেচিন্তে লেখা উত্তর,\\nনিয়ন্ত্রণ সবসময় আপনার হাতে।';

  @override
  String get onboardingPointConsentTitle =>
      'যে উত্তর আপনি অনুমোদন করবেন, সবসময়';

  @override
  String get onboardingPointConsentBody =>
      'ReplyMate উত্তর সাজেশন দেয়। আপনি দেখে, সম্পাদনা করে পাঠান - অ্যাপ নিজে থেকে কিছু পাঠায় না।';

  @override
  String get onboardingPointNotificationsTitle => 'নোটিফিকেশন থেকেই কাজ করে';

  @override
  String get onboardingPointNotificationsBody =>
      'আপনার অনুমতি নিয়ে এটি শুধু সেই অ্যাপগুলোর নোটিফিকেশন পড়ে যেগুলো আপনি বেছে নেন। কিছু অ্যাপ নোটিফিকেশনের লেখা লুকায় বা ছোট করে; তখন ReplyMate অনুমান না করে সেটা জানিয়ে দেয়।';

  @override
  String get onboardingPointLanguagesTitle => 'বাংলা, হিন্দি আর ইংরেজি';

  @override
  String get onboardingPointLanguagesBody =>
      'প্রতিটি উত্তরের ভাষা আর সুর বেছে নিন - বন্ধুত্বপূর্ণ, সহজ, পেশাদার, ভদ্র, মজার বা ছোট।';

  @override
  String get onboardingPointPrivacyTitle => 'গোপনীয়তা আগে';

  @override
  String get onboardingPointPrivacyBody =>
      'আপনি উত্তর চাইলে তবেই লেখাটি এআই সেবায় যায়, আর এই ফোনে কিছুই জমা থাকে না।';

  @override
  String get onboardingGetStarted => 'শুরু করুন';

  @override
  String get onboardingFooter =>
      'ReplyMate কী কী দেখতে পাবে, তা আপনি ঠিক করবেন।';

  @override
  String get permissionTitle => 'নোটিফিকেশন অ্যাক্সেস';

  @override
  String get permissionGranted => 'অনুমতি দেওয়া হয়েছে';

  @override
  String get permissionNeeded => 'বাবলের জন্য দরকার';

  @override
  String get permissionWhatAllows => 'এই অ্যাক্সেস কী কী করতে দেয়';

  @override
  String get permissionAllowsTitle => 'আপনি যে অ্যাপ বাছেন, তার নোটিফিকেশন';

  @override
  String get permissionAllowsBody =>
      'ReplyMate শুধু পরের স্ক্রিনে আপনি যে অ্যাপগুলো বাছবেন সেগুলোই প্রসেস করে, লেখাটি কেবল উত্তর লেখার জন্য ব্যবহার করে, আর কথোপকথন কখনো জমা রাখে না।';

  @override
  String get permissionNoReadTitle => 'অ্যাপের ভেতরে কিছু পড়ে না';

  @override
  String get permissionNoReadBody =>
      'স্ক্রিন ক্যাপচার নেই, অ্যাক্সেসিবিলিটি সার্ভিস নেই, মেসেজ পাঠানো নেই। যেকোনো সময় এখান থেকে বা Android সেটিংস থেকে অনুমতি বাতিল করতে পারেন।';

  @override
  String get permissionOpenSettings => 'Android সেটিংস খুলুন';

  @override
  String get permissionLater => 'পরে - আমি নিজে লেখা পেস্ট করব';

  @override
  String get permissionOptionalBubble => 'ঐচ্ছিক · ভাসমান রিপ্লাই বাবল';

  @override
  String get permissionOverlayGranted => 'ওভারলে অ্যাক্সেস দেওয়া হয়েছে';

  @override
  String get permissionOverlayNotGranted => 'ওভারলে অ্যাক্সেস দেওয়া হয়নি';

  @override
  String get permissionOverlayBody =>
      'মেসেজ এলে আপনি যে অ্যাপে আছেন তার উপরে একটি ছোট ReplyMate বাবল ভেসে থাকতে পারে, ফলে উত্তর এক ট্যাপ দূরত্বে।';

  @override
  String get permissionOverlayNotDoTitle => 'এটি যা করে না';

  @override
  String get permissionOverlayNotDoBody =>
      'এটি কখনো স্ক্রিন, নিচের অ্যাপ বা আপনার অনুরোধ ছাড়া অন্য কিছু পড়ে না।';

  @override
  String get permissionOverlayAndroid13 =>
      'Android 13 বা তার পরে নোটিফিকেশনও অনুমোদিত থাকতে হবে, যাতে "নতুন মেসেজ …" ফলব্যাক নোটিফিকেশনটি দেখা যায়।';

  @override
  String get permissionOpenOverlay => '"অন্য অ্যাপের উপরে দেখান" খুলুন';

  @override
  String get permissionManageOverlay => 'ওভারলে অ্যাক্সেস সামলান';

  @override
  String get appsTitle => 'সমর্থিত অ্যাপ';

  @override
  String get appsNothingYet => 'এখনো বেছে নেওয়ার কিছু নেই';

  @override
  String appsSelectedOf(int selected, int total) =>
      '$total-এর মধ্যে $selected বেছে নেওয়া হয়েছে';

  @override
  String get appsNoneInstalledTitle =>
      'এই ডিভাইসে সমর্থিত কোনো মেসেজিং অ্যাপ নেই।';

  @override
  String get appsNoneInstalledBody =>
      'লেখা পেস্ট করে বা বেছে নিয়ে আপনি তবুও ReplyMate ব্যবহার করতে পারেন।';

  @override
  String get appsReadFrom => 'যে অ্যাপগুলোর নোটিফিকেশন ReplyMate পড়তে পারে';

  @override
  String get appsNotificationsOnly =>
      'শুধু নোটিফিকেশন - অ্যাপের ভেতরে কখনো নয়';

  @override
  String get appsWhyListed =>
      'কোনো অ্যাপ এখানে আসে কেবল তখনই, যখন সেটি নোটিফিকেশন পাঠাতে দেখা গেছে।';

  @override
  String get appsReadFailed => 'ইনস্টল করা অ্যাপের তালিকা পড়া যায়নি।';

  @override
  String get readerTitle => 'স্ক্রিন রিডিং';

  @override
  String get readerWhatDoing => 'রিডার এখন কী করছে';

  @override
  String get readerRefresh => 'রিফ্রেশ';

  @override
  String get readerOpenSettings => 'Android সেটিংস খুলুন';

  @override
  String get readerNoAccessibility =>
      'এই ফোনে খোলার মতো অ্যাক্সেসিবিলিটি স্ক্রিন নেই। সেটিংস → অ্যাক্সেসিবিলিটি-তে দেখুন।';

  @override
  String get readerNoAnswer => 'নেটিভ দিক থেকে এখনো কোনো উত্তর আসেনি।';

  @override
  String get readerServiceStopped => 'সার্ভিস: চলছে না';

  @override
  String get readerSwitchOff => 'সুইচ: বন্ধ';

  @override
  String get readerWatchingNothing => 'দেখছে: কিছু বেছে নেওয়া হয়নি';

  @override
  String readerWatching(String apps) => 'দেখছে: $apps';

  @override
  String readerScans(int count) => 'স্ক্যান: $count';

  @override
  String readerLastScan(String summary) => 'শেষ স্ক্যান: $summary';

  @override
  String get readerNothingYet =>
      'এখনো পড়ার কিছু নেই - যে অ্যাপ দেখছেন সেখানে একটি চ্যাট খুলুন।';

  @override
  String readerSeen(String text) => 'দেখা গেছে: "$text"';
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
  // ------------------------------------------------------- setup path

  @override
  String get onboardingBadge => 'आपका एआई रिप्लाई सहायक';

  @override
  String get onboardingTitle => 'ReplyMate AI';

  @override
  String get onboardingSubtitle =>
      'आपकी भाषा में सोच-समझकर लिखा जवाब,\\nनियंत्रण हमेशा आपके पास।';

  @override
  String get onboardingPointConsentTitle => 'जवाब जिसे आप मंज़ूर करें, हमेशा';

  @override
  String get onboardingPointConsentBody =>
      'ReplyMate जवाब सुझाता है। आप देखकर, बदलकर भेजते हैं - ऐप खुद कुछ नहीं भेजता।';

  @override
  String get onboardingPointNotificationsTitle =>
      'नोटिफिकेशन से ही काम करता है';

  @override
  String get onboardingPointNotificationsBody =>
      'आपकी अनुमति से यह सिर्फ़ उन्हीं ऐप्स के नोटिफिकेशन पढ़ता है जिन्हें आप चुनते हैं। कुछ ऐप्स नोटिफिकेशन का टेक्स्ट छिपाते या छोटा करते हैं; तब ReplyMate अनुमान लगाने के बजाय बता देता है।';

  @override
  String get onboardingPointLanguagesTitle => 'बांग्ला, हिंदी और अंग्रेज़ी';

  @override
  String get onboardingPointLanguagesBody =>
      'हर जवाब की भाषा और लहजा चुनें - दोस्ताना, सहज, पेशेवर, विनम्र, मज़ेदार या छोटा।';

  @override
  String get onboardingPointPrivacyTitle => 'निजता पहले';

  @override
  String get onboardingPointPrivacyBody =>
      'टेक्स्ट एआई सेवा को सिर्फ़ तब जाता है जब आप जवाब मांगते हैं, और इस फ़ोन पर कुछ भी सेव नहीं होता।';

  @override
  String get onboardingGetStarted => 'शुरू करें';

  @override
  String get onboardingFooter =>
      'ReplyMate क्या देख सकता है, यह आप तय करते हैं।';

  @override
  String get permissionTitle => 'नोटिफिकेशन एक्सेस';

  @override
  String get permissionGranted => 'अनुमति दी गई';

  @override
  String get permissionNeeded => 'बबल के लिए ज़रूरी';

  @override
  String get permissionWhatAllows => 'यह एक्सेस क्या-क्या करने देता है';

  @override
  String get permissionAllowsTitle => 'आपके चुने हुए ऐप्स के नोटिफिकेशन';

  @override
  String get permissionAllowsBody =>
      'ReplyMate सिर्फ़ वही ऐप्स प्रोसेस करता है जो आप अगली स्क्रीन पर चुनते हैं, टेक्स्ट सिर्फ़ जवाब लिखने के लिए इस्तेमाल करता है, और बातचीत कभी सेव नहीं करता।';

  @override
  String get permissionNoReadTitle => 'ऐप्स के अंदर कुछ नहीं पढ़ता';

  @override
  String get permissionNoReadBody =>
      'कोई स्क्रीन कैप्चर नहीं, कोई एक्सेसिबिलिटी सेवा नहीं, कोई मैसेज भेजना नहीं। आप कभी भी यहाँ से या Android सेटिंग्स से अनुमति हटा सकते हैं।';

  @override
  String get permissionOpenSettings => 'Android सेटिंग्स खोलें';

  @override
  String get permissionLater => 'बाद में - मैं खुद टेक्स्ट पेस्ट करूँगा';

  @override
  String get permissionOptionalBubble => 'वैकल्पिक · फ़्लोटिंग रिप्लाई बबल';

  @override
  String get permissionOverlayGranted => 'ओवरले एक्सेस मिला है';

  @override
  String get permissionOverlayNotGranted => 'ओवरले एक्सेस नहीं मिला';

  @override
  String get permissionOverlayBody =>
      'मैसेज आने पर आप जिस ऐप में हैं उसके ऊपर एक छोटा ReplyMate बबल तैर सकता है, जिससे जवाब एक टैप दूर रहता है।';

  @override
  String get permissionOverlayNotDoTitle => 'यह क्या नहीं करता';

  @override
  String get permissionOverlayNotDoBody =>
      'यह कभी स्क्रीन, नीचे का ऐप या आपकी मांग के बिना कुछ नहीं पढ़ता।';

  @override
  String get permissionOverlayAndroid13 =>
      'Android 13 या बाद में नोटिफिकेशन भी अनुमत होना चाहिए, ताकि "नया मैसेज …" वाला फ़ॉलबैक नोटिफिकेशन दिख सके।';

  @override
  String get permissionOpenOverlay => '"अन्य ऐप्स के ऊपर दिखाएँ" खोलें';

  @override
  String get permissionManageOverlay => 'ओवरले एक्सेस प्रबंधित करें';

  @override
  String get appsTitle => 'समर्थित ऐप्स';

  @override
  String get appsNothingYet => 'अभी चुनने के लिए कुछ नहीं';

  @override
  String appsSelectedOf(int selected, int total) =>
      '$total में से $selected चुने गए';

  @override
  String get appsNoneInstalledTitle =>
      'इस डिवाइस पर कोई समर्थित मैसेजिंग ऐप नहीं है।';

  @override
  String get appsNoneInstalledBody =>
      'टेक्स्ट पेस्ट या चुनकर भी आप ReplyMate इस्तेमाल कर सकते हैं।';

  @override
  String get appsReadFrom => 'जिन ऐप्स के नोटिफिकेशन ReplyMate पढ़ सकता है';

  @override
  String get appsNotificationsOnly => 'सिर्फ़ नोटिफिकेशन - ऐप के अंदर कभी नहीं';

  @override
  String get appsWhyListed =>
      'कोई ऐप यहाँ सिर्फ़ तब आता है जब उसे नोटिफिकेशन भेजते देखा गया हो।';

  @override
  String get appsReadFailed => 'इंस्टॉल किए ऐप्स की सूची नहीं पढ़ी जा सकी।';

  @override
  String get readerTitle => 'स्क्रीन रीडिंग';

  @override
  String get readerWhatDoing => 'रीडर अभी क्या कर रहा है';

  @override
  String get readerRefresh => 'रिफ़्रेश';

  @override
  String get readerOpenSettings => 'Android सेटिंग्स खोलें';

  @override
  String get readerNoAccessibility =>
      'इस फ़ोन में खोलने के लिए कोई एक्सेसिबिलिटी स्क्रीन नहीं है। सेटिंग्स → एक्सेसिबिलिटी में देखें।';

  @override
  String get readerNoAnswer => 'नेटिव साइड से अभी कोई जवाब नहीं आया।';

  @override
  String get readerServiceStopped => 'सेवा: चल नहीं रही';

  @override
  String get readerSwitchOff => 'स्विच: बंद';

  @override
  String get readerWatchingNothing => 'देख रहा है: कुछ चुना नहीं गया';

  @override
  String readerWatching(String apps) => 'देख रहा है: $apps';

  @override
  String readerScans(int count) => 'स्कैन: $count';

  @override
  String readerLastScan(String summary) => 'पिछला स्कैन: $summary';

  @override
  String get readerNothingYet =>
      'अभी पढ़ने के लिए कुछ नहीं - जिस ऐप को देख रहे हैं वहाँ कोई चैट खोलें।';

  @override
  String readerSeen(String text) => 'देखा गया: "$text"';
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
