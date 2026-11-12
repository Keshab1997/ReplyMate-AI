import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/app/app_shell.dart';
import 'package:replymate/features/home/home_screen.dart';
import 'package:replymate/shared/widgets/mascot_face.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Three promises, tested instead of assumed: Home survives large text sizes,
/// every destination in the tab bar is announced by name, and the decorating
/// mascot stays out of the reading order.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The Home screen reads notification state from the native layer; the
    // honest "nothing is granted" answer keeps it to the UI under test.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.keshabstudios.replymate/notifications'),
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        'overlayGranted' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.keshabstudios.replymate/notifications'),
      null,
    );
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required double textScale,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home survives 2x text without overflowing', (tester) async {
    // The old quick-start grid had a fixed aspect ratio: at 2x the labels were
    // clipped and Flutter logged an overflow. The grid is gone (the four tiles
    // became the four tabs) but the promise stays: nothing overflows at 2x.
    await pumpHome(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('Generate a reply'), findsOneWidget);
  });

  testWidgets('every tab is announced by name', (tester) async {
    // The four quick-start tiles carried a merged one-sentence label each.
    // They are tabs now, so the promise moves to the tab bar: a screen reader
    // must hear where each destination goes, not just see an icon.
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppShell())),
    );
    await tester.pumpAndSettle();

    // Flutter appends the position itself, so TalkBack reads "Home, tab 1 of
    // 4" - the destination and where it sits in the bar, both out loud.
    for (final label in const ['Home', 'Reply', 'Apps', 'Settings']) {
      expect(
        find.bySemanticsLabel(RegExp('^$label\nTab')),
        findsOneWidget,
        reason: '$label is announced as a tab',
      );
    }
    semantics.dispose();
  });

  testWidgets('the mascot is decoration unless it is given a meaning', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MascotFace(size: 48, animate: false),
              MascotFace(
                size: 48,
                animate: false,
                mood: MascotMood.thinking,
                semanticLabel: 'Thinking',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One is silent, exactly one carries the label.
    expect(find.bySemanticsLabel('Thinking'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('reduced motion stops the bob', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: MascotFace(size: 64))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Nothing is driving frames: the platform asked for no animation.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
