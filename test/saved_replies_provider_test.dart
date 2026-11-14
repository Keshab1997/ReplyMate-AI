import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/reply/providers/saved_replies_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'saves trimmed user-authored templates locally and rejects duplicates',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(savedRepliesProvider);
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(savedRepliesProvider.notifier);
      expect(await notifier.add('  Thanks, I will check.  '), isTrue);
      expect(await notifier.add('Thanks, I will check.'), isFalse);
      expect(container.read(savedRepliesProvider), ['Thanks, I will check.']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AppConstants.prefSavedReplies), [
        'Thanks, I will check.',
      ]);
    },
  );

  test('removes templates and deletes the preference when empty', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefSavedReplies: ['Will reply soon'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(savedRepliesProvider);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(savedRepliesProvider.notifier)
        .remove('Will reply soon');
    expect(container.read(savedRepliesProvider), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AppConstants.prefSavedReplies), isFalse);
  });
}
