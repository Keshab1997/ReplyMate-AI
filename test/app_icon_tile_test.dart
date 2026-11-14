import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/core/platform/notifications_bridge.dart';
import 'package:replymate/features/app_selection/app_selection_screen.dart';
import 'package:replymate/shared/widgets/app_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real 1×1 PNG. Small enough to inline, and it exercises the decode path
/// the way a launcher icon would.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const MethodChannel _bridgeChannel = MethodChannel(AppConstants.channelName);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridgeChannel,
      null,
    );
  });

  testWidgets('an app with an icon shows the launcher artwork', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconTile(label: 'WhatsApp', icon: _pngBytes),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('W'), findsNothing);
  });

  testWidgets('a missing icon degrades to the initial, same size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppIconTile(label: 'Telegram')),
      ),
    );
    await tester.pump();

    expect(find.text('T'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    // The placeholder keeps the row's geometry: a missing icon must never
    // change the height of the list.
    expect(tester.getSize(find.byType(AppIconTile)), const Size(40, 40));
  });

  testWidgets('corrupt icon bytes fall back instead of erroring', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconTile(
            label: 'Signal',
            icon: Uint8List.fromList(<int>[1, 2, 3, 4]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('S'), findsOneWidget);
  });

  test('candidateApps carries icon bytes through the channel', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridgeChannel,
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[
          <String, Object?>{
            'packageName': 'com.whatsapp',
            'label': 'WhatsApp',
            'iconBytes': _pngBytes,
          },
          <String, Object?>{'packageName': 'com.telegram', 'label': 'Telegram'},
        ],
        _ => null,
      },
    );

    final apps = await NotificationsBridge(channel: _bridgeChannel)
        .candidateApps();

    expect(apps.first.icon, _pngBytes);
    // No icon key at all is a normal answer, not a parse failure.
    expect(apps.last.icon, isNull);
    expect(apps.last.label, 'Telegram');
  });

  testWidgets('the Apps tab draws a tile for every installed app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridgeChannel,
      (call) async => switch (call.method) {
        'candidateApps' => <Object?>[
          <String, Object?>{
            'packageName': 'com.whatsapp',
            'label': 'WhatsApp',
            'iconBytes': _pngBytes,
          },
        ],
        'isListenerEnabled' => false,
        _ => null,
      },
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppSelectionScreen(embedded: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.byType(AppIconTile), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
