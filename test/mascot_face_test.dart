import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/shared/widgets/mascot_face.dart';

/// The mascot is the app's only animated element, so its two promises are
/// tested directly: it shows a "working" cue only while it is thinking, and it
/// leaves nothing running behind a disposed screen.
void main() {
  const dots = Key('mascot-thinking-dots');

  Future<void> pump(WidgetTester tester, MascotMood mood) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: MascotFace(size: 64, mood: mood, animate: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a thinking face shows the dots', (tester) async {
    await pump(tester, MascotMood.thinking);
    expect(find.byKey(dots), findsOneWidget);
  });

  testWidgets('every other mood stays wordless and dotless', (tester) async {
    for (final mood in [
      MascotMood.idle,
      MascotMood.listening,
      MascotMood.happy,
      MascotMood.alert,
    ]) {
      await pump(tester, mood);
      expect(find.byKey(dots), findsNothing, reason: '$mood should be quiet');
    }
  });

  testWidgets('happy and alert moods use their own artwork', (tester) async {
    for (final (mood, asset) in [
      (MascotMood.happy, 'assets/mascot/mascot_face_happy.png'),
      (MascotMood.alert, 'assets/mascot/mascot_face_alert.png'),
    ]) {
      await pump(tester, mood);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == asset,
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('the animated face settles instead of ticking forever', (
    tester,
  ) async {
    // An infinite ticker would hang pumpAndSettle; the bob is deliberately
    // finite, so this returns.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: MascotFace(size: 64, mood: MascotMood.thinking)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(dots), findsOneWidget);
  });
}
