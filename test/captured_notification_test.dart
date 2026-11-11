import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/prompt_builder.dart';
import 'package:replymate/features/reply/domain/reply_request.dart';

// Every parameter is Object? on purpose: the point of several tests is that
// wrongly-typed wire values degrade safely instead of throwing.
Map<Object?, Object?> wire({
  Object? packageName = 'com.whatsapp',
  Object? key = 'sbn-1',
  Object? title = 'Asha',
  Object? text = 'Can we meet tomorrow afternoon?',
  Object? isTruncated = false,
  Object? isGrouped = false,
  Object? isGroupSummary = false,
  Object? mayBeRedacted = false,
  Object? hasReplyAction = true,
  Object? replyActionLabel = 'Reply',
  Object? postedAtMillis = 1700000000000,
}) => {
  'packageName': packageName,
  'key': key,
  'title': title,
  'text': text,
  'isTruncated': isTruncated,
  'isGrouped': isGrouped,
  'isGroupSummary': isGroupSummary,
  'mayBeRedacted': mayBeRedacted,
  'hasReplyAction': hasReplyAction,
  'replyActionLabel': replyActionLabel,
  'postedAtMillis': postedAtMillis,
};

void main() {
  group('CapturedNotification.fromMap', () {
    test('parses a complete event', () {
      final notification = CapturedNotification.fromMap(wire());
      expect(notification.packageName, 'com.whatsapp');
      expect(notification.hasText, isTrue);
      expect(notification.displayText, 'Can we meet tomorrow afternoon?');
      expect(notification.displayTitle, 'Asha');
      expect(notification.hasReplyAction, isTrue);
      expect(notification.contextWarnings, isEmpty);
    });

    test('missing text is a normal state, not an error (FR-04)', () {
      final notification = CapturedNotification.fromMap(wire(text: null));
      expect(notification.hasText, isFalse);
      expect(notification.displayText, '');
      expect(
        notification.contextWarnings,
        contains('no message text available'),
      );
    });

    test('whitespace-only text counts as missing', () {
      final notification = CapturedNotification.fromMap(wire(text: '   '));
      expect(notification.hasText, isFalse);
    });

    test('missing title falls back to the package name', () {
      final notification = CapturedNotification.fromMap(wire(title: null));
      expect(notification.displayTitle, 'com.whatsapp');
    });

    test('truncation is always reported - the text really is cut', () {
      final notification = CapturedNotification.fromMap(
        wire(isTruncated: true),
      );
      expect(notification.contextWarnings, <String>['text may be truncated']);
    });

    test('a plain chat with text reports no noise', () {
      // WhatsApp sets a group key on every chat and a non-public visibility on
      // most messages; both used to produce "grouped notification · may be
      // redacted" under a perfectly complete message, which taught the user to
      // ignore the honest warnings.
      final notification = CapturedNotification.fromMap(
        wire(isGrouped: true, mayBeRedacted: true),
      );
      expect(notification.hasText, isTrue);
      expect(notification.contextWarnings, isEmpty);
    });

    test('a summary with no text reports everything that applies', () {
      final notification = CapturedNotification.fromMap(
        wire(
          text: null,
          isGrouped: true,
          isGroupSummary: true,
          mayBeRedacted: true,
        ),
      );
      expect(notification.contextWarnings, hasLength(3));
      expect(
        notification.contextWarnings,
        containsAll(<String>[
          'no message text available',
          'may be redacted by privacy settings',
          'grouped notification',
        ]),
      );
    });

    test('wrong-typed content fields degrade to null instead of throwing', () {
      final notification = CapturedNotification.fromMap(
        wire(
          title: 42,
          text: <int>[],
          replyActionLabel: true,
          postedAtMillis: 'x',
        ),
      );
      expect(notification.title, isNull);
      expect(notification.text, isNull);
      expect(notification.replyActionLabel, isNull);
      expect(notification.postedAtMillis, 0);
    });

    test('wrong-typed flags read as false', () {
      final notification = CapturedNotification.fromMap(
        wire(isTruncated: 'yes', hasReplyAction: 1),
      );
      expect(notification.isTruncated, isFalse);
      expect(notification.hasReplyAction, isFalse);
    });

    test('structural fields are strict: no packageName is untrusted', () {
      expect(
        () => CapturedNotification.fromMap(wire(packageName: '')),
        throwsFormatException,
      );
      expect(
        () => CapturedNotification.fromMap(wire(key: null)),
        throwsFormatException,
      );
    });
  });

  testWidgets('prior messages travel with the capture', (tester) async {
    final notification = CapturedNotification.fromMap(<Object?, Object?>{
      'packageName': 'com.whatsapp',
      'key': 'sbn-1',
      'title': 'Asha',
      'text': 'Shall we move it to Friday?',
      'priorMessages': <Object?>['Are we still on for tomorrow?', 'Yes - 4pm?'],
      'isTruncated': false,
      'isGrouped': false,
      'isGroupSummary': false,
      'mayBeRedacted': false,
      'hasReplyAction': true,
      'postedAtMillis': 1,
    });

    expect(notification.priorMessages, <String>[
      'Are we still on for tomorrow?',
      'Yes - 4pm?',
    ]);
  });

  testWidgets('a capture with no history is normal, not a failure', (
    tester,
  ) async {
    final notification = CapturedNotification.fromMap(<Object?, Object?>{
      'packageName': 'com.whatsapp',
      'key': 'sbn-1',
      'text': 'Hi',
      'isTruncated': false,
      'isGrouped': false,
      'isGroupSummary': false,
      'mayBeRedacted': false,
      'hasReplyAction': false,
      'postedAtMillis': 1,
    });

    expect(notification.priorMessages, isEmpty);
  });

  testWidgets('wrong-typed history degrades to empty', (tester) async {
    final notification = CapturedNotification.fromMap(<Object?, Object?>{
      'packageName': 'com.whatsapp',
      'key': 'sbn-1',
      'text': 'Hi',
      'priorMessages': 'not a list',
      'isTruncated': false,
      'isGrouped': false,
      'isGroupSummary': false,
      'mayBeRedacted': false,
      'hasReplyAction': false,
      'postedAtMillis': 1,
    });

    expect(notification.priorMessages, isEmpty);
  });

  testWidgets('the history reaches the prompt', (tester) async {
    // "Shall we move it to Friday?" is unanswerable on its own; the lines that
    // led up to it are what make the reply make sense.
    final request = ReplyRequest(
      message: 'Shall we move it to Friday?',
      language: ReplyLanguage.english,
      tone: ReplyTone.friendly,
      length: ReplyLength.short,
      count: 1,
      priorMessages: const ['Are we still on for tomorrow?', 'Yes - 4pm?'],
    );

    final prompt = ReplyPrompt.user(request);

    expect(prompt, contains('Earlier in this conversation'));
    expect(prompt, contains('- Are we still on for tomorrow?'));
    expect(prompt, contains('- Yes - 4pm?'));
    // The history sits before the message, never after it.
    expect(
      prompt.indexOf('Earlier in this conversation'),
      lessThan(prompt.indexOf('Incoming message')),
    );
  });

  testWidgets('no history means no history section', (tester) async {
    final request = ReplyRequest(
      message: 'Hi',
      language: ReplyLanguage.english,
      tone: ReplyTone.friendly,
      length: ReplyLength.short,
      count: 1,
    );

    expect(ReplyPrompt.user(request), isNot(contains('Earlier in')));
  });

  group('history authors', () {
    test('a screen-read capture carries who said each line', () {
      final capture = CapturedNotification.fromMap({
        'packageName': 'com.whatsapp',
        'key': 'screen:com.whatsapp:1',
        'title': 'Riya',
        'text': 'tahole kal dekha hobe',
        'priorMessages': ['kal dekha hobe?', 'haan ashchi'],
        'priorAuthors': ['them', 'me'],
        'fromScreen': true,
      });

      expect(capture.hasTaggedHistory, isTrue);
      expect(capture.priorAuthors, ['them', 'me']);
    });

    test('a notification capture has no authors, and says so', () {
      final capture = CapturedNotification.fromMap({
        'packageName': 'com.whatsapp',
        'key': 'k',
        'text': 'hello',
        'priorMessages': ['something older'],
      });

      // Unknown, not "them": the difference is what stops memory from filing the
      // user's own words as the sender's.
      expect(capture.priorAuthors, isEmpty);
      expect(capture.hasTaggedHistory, isFalse);
    });

    test('a half-tagged history is not a tagged one', () {
      final capture = CapturedNotification.fromMap({
        'packageName': 'com.whatsapp',
        'key': 'k',
        'text': 'hello',
        'priorMessages': ['one', 'two'],
        'priorAuthors': ['me'],
      });

      expect(capture.hasTaggedHistory, isFalse);
    });

    test('an unknown author value reads as them, never as the user', () {
      final capture = CapturedNotification.fromMap({
        'packageName': 'com.whatsapp',
        'key': 'k',
        'text': 'hello',
        'priorMessages': ['one'],
        'priorAuthors': ['someone-else'],
      });

      // Fail safe: claiming a line is the user's own would put words in their
      // mouth in the next draft.
      expect(capture.priorAuthors, ['them']);
      expect(capture.hasTaggedHistory, isTrue);
    });
  });
}
