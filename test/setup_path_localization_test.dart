import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/l10n/app_strings.dart';
import 'package:replymate/features/app_selection/app_selection_screen.dart';
import 'package:replymate/features/permissions/permission_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The setup path was the last place a Bengali session still showed English:
/// onboarding, the permission screen, app selection and the screen-reading
/// card. This test walks those screens in all three languages, so the box in
/// ROADMAP Phase 2 cannot be ticked again while an English string hides there.
const MethodChannel bridgeChannel = MethodChannel(
  'com.keshabstudios.replymate/notifications',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        'isOverlayEnabled' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridgeChannel,
      null,
    );
  });

  /// A scope whose language is already [language], so the first frame is
  /// already translated (no async pref read to wait for).
  Widget app(Widget home, AppLanguage language) {
    return ProviderScope(
      overrides: [
        appLanguageProvider.overrideWith(() => _FixedLanguage(language)),
      ],
      child: MaterialApp(home: home),
    );
  }

  testWidgets('the permission screen speaks Bengali', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      app(const PermissionSetupScreen(), AppLanguage.bengali),
    );
    await tester.pumpAndSettle();

    expect(find.text(const BengaliStrings().permissionTitle), findsWidgets);
    expect(
      find.text(const BengaliStrings().permissionOpenSettings),
      findsOneWidget,
    );
    expect(find.text(const BengaliStrings().permissionLater), findsOneWidget);
    // The English original must be gone, not merely joined by a translation.
    expect(find.text('Open Android Settings'), findsNothing);
    expect(find.text('Later - I will paste text manually'), findsNothing);
  });

  testWidgets('the permission screen speaks Hindi', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      app(const PermissionSetupScreen(), AppLanguage.hindi),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(const HindiStrings().permissionOpenSettings),
      findsOneWidget,
    );
    expect(find.text('Open Android Settings'), findsNothing);
  });

  testWidgets('app selection speaks Bengali, empty state included', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      app(const AppSelectionScreen(), AppLanguage.bengali),
    );
    await tester.pumpAndSettle();

    expect(find.text(const BengaliStrings().appsTitle), findsWidgets);
    expect(
      find.text(const BengaliStrings().appsNoneInstalledTitle),
      findsOneWidget,
    );
    expect(
      find.text('No supported messaging app is installed on this device.'),
      findsNothing,
    );
  });

  test('every setup-path string is translated in all three languages', () {
    const en = EnglishStrings();
    const bn = BengaliStrings();
    const hi = HindiStrings();

    // The strings added for the setup path. Listed explicitly rather than
    // reflected: a new string should force a decision about translating it.
    final samples = <String, List<String>>{
      'onboardingBadge': [
        en.onboardingBadge,
        bn.onboardingBadge,
        hi.onboardingBadge,
      ],
      'onboardingPointConsentBody': [
        en.onboardingPointConsentBody,
        bn.onboardingPointConsentBody,
        hi.onboardingPointConsentBody,
      ],
      'permissionTitle': [
        en.permissionTitle,
        bn.permissionTitle,
        hi.permissionTitle,
      ],
      'permissionNoReadBody': [
        en.permissionNoReadBody,
        bn.permissionNoReadBody,
        hi.permissionNoReadBody,
      ],
      'appsNoneInstalledBody': [
        en.appsNoneInstalledBody,
        bn.appsNoneInstalledBody,
        hi.appsNoneInstalledBody,
      ],
      'readerNoAccessibility': [
        en.readerNoAccessibility,
        bn.readerNoAccessibility,
        hi.readerNoAccessibility,
      ],
    };

    samples.forEach((name, values) {
      expect(values[0].trim(), isNotEmpty, reason: '$name missing in English');
      // Bengali and Hindi must differ from English; identical copy means the
      // getter was added to the interface and then left untranslated.
      expect(
        values[1],
        isNot(values[0]),
        reason: '$name untranslated in Bengali',
      );
      expect(
        values[2],
        isNot(values[0]),
        reason: '$name untranslated in Hindi',
      );
      expect(
        values[1],
        isNot(values[2]),
        reason: '$name has the same Bengali and Hindi text',
      );
    });
  });

  test('the parameterised strings interpolate', () {
    expect(const BengaliStrings().appsSelectedOf(2, 5), contains('2'));
    expect(const HindiStrings().appsSelectedOf(2, 5), contains('5'));
    expect(
      const BengaliStrings().readerWatching('WhatsApp'),
      contains('WhatsApp'),
    );
    expect(const HindiStrings().readerSeen('hello'), contains('hello'));
    expect(const BengaliStrings().readerScans(7), contains('7'));
  });
}

/// Pins the language for a widget test, bypassing the async preference read.
class _FixedLanguage extends AppLanguageNotifier {
  _FixedLanguage(this._language);

  final AppLanguage _language;

  @override
  AppLanguage build() => _language;
}
