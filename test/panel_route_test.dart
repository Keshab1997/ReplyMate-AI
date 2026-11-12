import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/app/app.dart';
import 'package:replymate/app/app_routes.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The panel must never be a door into the main app.
///
/// Flutter's default initial-route handling built `/` underneath `/overlay`, so
/// the transparent panel activity had ReplyMate sitting behind its barrier:
/// tapping the empty space around the panel popped the panel and showed the app
/// over the chat. These two tests pin the fix.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppConstants.channelName);
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return switch (call.method) {
        'consumeOverlayContext' => null,
        'peekOverlayContexts' => <Object?>[],
        'candidateApps' => <Object?>[],
        'isListenerEnabled' => false,
        'overlayGranted' => false,
        _ => null,
      };
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('launching the panel does not stack the main app under it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: ReplyMateApp(initialRoute: AppRoutes.overlay)),
    );
    await tester.pumpAndSettle();

    // The panel is the only route: nothing to reveal, nothing to pop into.
    expect(find.byType(HomeScreen), findsNothing);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('an empty tap asks the platform to close the panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: ReplyMateApp(initialRoute: AppRoutes.overlay)),
    );
    await tester.pumpAndSettle();

    // Top-left corner: outside the sheet, over the barrier.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(calls, contains('closeOverlayPanel'));
    expect(find.byType(HomeScreen), findsNothing);
  });
}
