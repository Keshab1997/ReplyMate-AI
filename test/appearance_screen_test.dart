import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replymate/app/theme/app_theme.dart';
import 'package:replymate/app/theme/app_theme_preferences.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/settings/presentation/appearance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('each palette produces its own light and dark accent', () {
    final colors = AppPalette.values
        .map((palette) => AppTheme.light(palette: palette).colorScheme.primary)
        .toSet();

    expect(colors, hasLength(AppPalette.values.length));
    for (final palette in AppPalette.values) {
      expect(
        AppTheme.dark(palette: palette).colorScheme.primary,
        palette.bright,
      );
    }
  });

  testWidgets('appearance controls fit on a narrow Bengali screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefAppLanguage: 'bn',
    });
    tester.view.physicalSize = const Size(640, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppearanceScreen())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('palette and brightness changes persist independently', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppearanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lavender'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.text('Rose'), findsOneWidget);
    expect(find.text('Amber'), findsOneWidget);
    expect(find.text('Ocean'), findsOneWidget);

    await tester.tap(find.text('Forest'));
    await tester.pumpAndSettle();
    expect(
      container.read(appThemePreferencesProvider).palette,
      AppPalette.forest,
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      container.read(appThemePreferencesProvider).mode,
      AppAppearanceMode.dark,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.prefThemePalette), 'forest');
    expect(prefs.getString(AppConstants.prefThemeMode), 'dark');
  });
}
