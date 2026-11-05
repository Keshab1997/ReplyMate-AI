import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/notifications/models/launch_context.dart';

void main() {
  group('LaunchContext.fromMap', () {
    test('process_text carries the selected text', () {
      final context = LaunchContext.fromMap({
        'source': 'process_text',
        'text': 'Kal raat 8tay call korio',
      });
      expect(context.source, LaunchSource.processText);
      expect(context.hasText, isTrue);
      expect(context.text, 'Kal raat 8tay call korio');
    });

    test('share carries the shared text', () {
      final context = LaunchContext.fromMap({
        'source': 'share',
        'text': 'Meeting moved to 5.',
      });
      expect(context.source, LaunchSource.share);
    });

    test('unknown or missing source degrades to manual', () {
      expect(
        LaunchContext.fromMap({'source': 'telepathy', 'text': 'x'}).source,
        LaunchSource.manual,
      );
      expect(LaunchContext.fromMap({'text': 'x'}).source, LaunchSource.manual);
    });

    test('missing or blank text means no context', () {
      expect(LaunchContext.fromMap({'source': 'share'}).hasText, isFalse);
      expect(
        LaunchContext.fromMap({'source': 'share', 'text': '  '}).hasText,
        isFalse,
      );
    });

    test('source labels are user-facing sentences', () {
      expect(LaunchSource.processText.label, 'Selected in another app');
      expect(LaunchSource.share.label, 'Shared from another app');
      expect(LaunchSource.manual.label, 'Typed or pasted here');
    });
  });
}
