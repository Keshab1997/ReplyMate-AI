import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/app_selection/app_selection_screen.dart';
import 'package:replymate/features/permissions/permission_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Outbound calls on the bridge channel hang in widget tests when the app has
/// registered an inbound handler on the same channel (startListening) but no
/// mock exists — the test messenger loops the call back and nothing answers.
/// Mock the honest no-native-layer answers: no candidates, listener off.
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

  testWidgets(
    'permission screen explains before asking and offers a manual path',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: PermissionSetupScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notification access not granted'), findsOneWidget);
      expect(find.text('Open Android Settings'), findsOneWidget);
      expect(find.text('Later - I will paste text manually'), findsOneWidget);
      expect(find.textContaining('No reading inside apps'), findsOneWidget);
    },
  );

  testWidgets('app selection with no installed candidates says so honestly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppSelectionScreen())),
    );
    // The candidate list comes from the native layer; in tests the channel
    // has no handler, so the honest empty state must render.
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No supported messaging app is installed'),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
  });
}
