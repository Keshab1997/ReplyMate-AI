import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/app/theme/app_theme.dart';
import 'package:replymate/shared/widgets/brand_icon.dart';

void main() {
  test('light and dark themes share the bundled multilingual fonts', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        containsAll(<String>['NotoSansBengali', 'NotoSansDevanagari']),
      );
    }
  });

  testWidgets('custom icons and bundled scripts render together', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              for (final type in BrandIconType.values)
                BrandIcon(type: type, color: AppTheme.brand),
              const Text('বাংলা উত্তর · हिंदी उत्तर · English reply'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BrandIcon), findsNWidgets(BrandIconType.values.length));
    expect(
      find.text('বাংলা উত্তর · हिंदी उत्तर · English reply'),
      findsOneWidget,
    );
  });
}
