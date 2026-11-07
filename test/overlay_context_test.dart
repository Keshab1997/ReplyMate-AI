import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/overlay/models/overlay_context.dart';

/// One row of the `consumeOverlayContext` wire format
/// (docs/PLATFORM_CHANNELS.md) with every field set.
Map<Object?, Object?> _fullWire({String source = 'bubble'}) =>
    <Object?, Object?>{
      'source': source,
      'packageName': 'com.whatsapp',
      'key': 'sbn-42',
      'title': 'Asha',
      'text': 'Can we meet tomorrow?',
      'isTruncated': true,
      'isGrouped': true,
      'isGroupSummary': false,
      'mayBeRedacted': true,
      'hasReplyAction': true,
      'replyActionLabel': 'Reply',
      'postedAtMillis': 1730000000000,
    };

void main() {
  group('OverlayContext.fromMap', () {
    test('reads every row of the wire table', () {
      final context = OverlayContext.fromMap(_fullWire());
      final notification = context.notification;

      expect(context.source, OverlaySource.bubble);
      expect(context.opensPanel, isTrue);
      expect(notification.packageName, 'com.whatsapp');
      expect(notification.key, 'sbn-42');
      expect(notification.title, 'Asha');
      expect(notification.text, 'Can we meet tomorrow?');
      expect(notification.isTruncated, isTrue);
      expect(notification.isGrouped, isTrue);
      expect(notification.isGroupSummary, isFalse);
      expect(notification.mayBeRedacted, isTrue);
      expect(notification.hasReplyAction, isTrue);
      expect(notification.replyActionLabel, 'Reply');
      expect(notification.postedAtMillis, 1730000000000);
    });

    test('a fallback context does not open the panel', () {
      final context = OverlayContext.fromMap(_fullWire(source: 'fallback'));
      expect(context.source, OverlaySource.fallback);
      expect(context.opensPanel, isFalse);
    });

    test('an unknown source degrades to the conservative composer path', () {
      // Not the panel: a source we do not understand must never produce a
      // floating window the user cannot explain.
      final context = OverlayContext.fromMap(_fullWire(source: 'telepathy'));
      expect(context.source, OverlaySource.fallback);
      expect(context.opensPanel, isFalse);
    });

    test('a missing source is read as fallback', () {
      final wire = _fullWire()..remove('source');
      expect(OverlayContext.fromMap(wire).source, OverlaySource.fallback);
    });

    test('missing packageName or key is refused, not guessed', () {
      for (final missing in ['packageName', 'key']) {
        final wire = _fullWire()..remove(missing);
        expect(
          () => OverlayContext.fromMap(wire),
          throwsFormatException,
          reason:
              'a context without $missing cannot be attributed to a message',
        );
      }
    });

    test('a minimal map yields honest defaults, not stale values', () {
      final context = OverlayContext.fromMap(<Object?, Object?>{
        'packageName': 'com.whatsapp',
        'key': 'sbn-1',
      });
      final notification = context.notification;

      expect(notification.title, isNull);
      expect(notification.text, isNull);
      expect(notification.hasText, isFalse);
      expect(notification.isTruncated, isFalse);
      expect(notification.mayBeRedacted, isFalse);
      expect(notification.hasReplyAction, isFalse);
      expect(notification.postedAtMillis, 0);
      expect(context.contextWarnings, contains('no message text available'));
    });

    test('appLabel names a known app and never invents one', () {
      expect(OverlayContext.fromMap(_fullWire()).appLabel, 'WhatsApp');

      final unknown = OverlayContext.fromMap(<Object?, Object?>{
        'packageName': 'com.example.chat',
        'key': 'sbn-9',
        'source': 'bubble',
      });
      // The package id is the honest fallback: better than a guess.
      expect(unknown.appLabel, 'com.example.chat');
    });

    test('toString never leaks the message text', () {
      final context = OverlayContext.fromMap(_fullWire());
      expect(context.toString(), isNot(contains('Can we meet tomorrow?')));
    });
  });
}
