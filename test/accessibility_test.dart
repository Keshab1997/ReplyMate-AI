import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/home/home_screen.dart';
import 'package:replymate/shared/widgets/mascot_face.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Three promises, tested instead of assumed: Home survives large text sizes,
/// every tappable tile says one clear thing to TalkBack, and the decorating
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
    // clipped and Flutter logged an overflow. This is the regression test.
    await pumpHome(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('Paste a message'), findsOneWidget);
  });

  testWidgets('a tile reads as one sentence to TalkBack', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester, textScale: 1.0);
    expect(
      find.bySemanticsLabel('Paste a message. Reply to the chat you are in'),
      findsOneWidget,
    );
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
