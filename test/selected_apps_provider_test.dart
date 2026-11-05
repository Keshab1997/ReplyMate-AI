import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/app_selection/providers/selected_apps_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stored selection is loaded at startup', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefSelectedApps: ['org.telegram.messenger'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(selectedAppsProvider.notifier).ready;
    expect(container.read(selectedAppsProvider), ['org.telegram.messenger']);
  });

  test('toggle persists and mirrors down to the native layer', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedAppsProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    await notifier.toggle('com.whatsapp');
    expect(container.read(selectedAppsProvider), ['com.whatsapp']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(AppConstants.prefSelectedApps), [
      'com.whatsapp',
    ]);

    // Tapping again revokes: an empty allowlist means the native listener
    // processes nothing at all.
    await notifier.toggle('com.whatsapp');
    expect(container.read(selectedAppsProvider), isEmpty);
    expect(prefs.getStringList(AppConstants.prefSelectedApps), isEmpty);
  });

  test('clear empties selection and storage', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefSelectedApps: ['com.whatsapp', 'com.android.mms'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedAppsProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(selectedAppsProvider), hasLength(2));

    await notifier.clear();
    expect(container.read(selectedAppsProvider), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(AppConstants.prefSelectedApps), isNull);
  });
}
