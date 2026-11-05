import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/notifications/models/captured_notification.dart';

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

    test('truncated, grouped and redacted flags surface as warnings', () {
      final notification = CapturedNotification.fromMap(
        wire(isTruncated: true, isGrouped: true, mayBeRedacted: true),
      );
      expect(notification.contextWarnings, hasLength(3));
      expect(notification.contextWarnings, contains('text may be truncated'));
      expect(notification.contextWarnings, contains('grouped notification'));
      expect(
        notification.contextWarnings,
        contains('may be redacted by privacy settings'),
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
}
