import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_constants.dart';
import 'package:replymate/features/screen_reading/models/screen_reading_status.dart';
import 'package:replymate/features/screen_reading/widgets/screen_reading_status_card.dart';

// Every parameter is Object? on purpose: the point of several tests is that
// wrongly-typed wire values degrade instead of throwing.
Map<Object?, Object?> wire({
  Object? connected = true,
  Object? enabledByUser = true,
  Object? allowlist = const <Object?>['com.whatsapp'],
  Object? scanCount = 3,
  Object? lastScanAtMillis = 1700000000000,
  Object? listCount = 1,
  Object? rowCount = 6,
  Object? lastOutcome = 'read',
  Object? lastText = 'kalke meeting e ashbe?',
  Object? lastPackage = 'com.whatsapp',
}) => <Object?, Object?>{
  'connected': connected,
  'enabledByUser': enabledByUser,
  'allowlist': allowlist,
  'scanCount': scanCount,
  'lastScanAtMillis': lastScanAtMillis,
  'listCount': listCount,
  'rowCount': rowCount,
  'lastOutcome': lastOutcome,
  'lastText': lastText,
  'lastPackage': lastPackage,
};

/// The outcomes the native side can report, and nothing else.
const outcomes = <String>[
  'read',
  'no_window',
  'other_app',
  'no_list',
  'no_rows',
  'no_message',
  'outgoing',
  'not_new',
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('a full report parses', () {
    final status = ScreenReadingStatus.fromMap(wire());

    expect(status.connected, isTrue);
    expect(status.enabledByUser, isTrue);
    expect(status.allowlist, <String>['com.whatsapp']);
    expect(status.scanCount, 3);
    expect(status.rowCount, 6);
    expect(status.lastText, 'kalke meeting e ashbe?');
    expect(status.hasScanned, isTrue);
    expect(status.summary, 'Read a message.');
  });

  test('every outcome has a sentence a person can act on', () {
    // The whole point of the report: "no_rows" tells nobody anything, while
    // "the list was there but no row looked readable" points at the fix.
    for (final outcome in outcomes) {
      final status = ScreenReadingStatus.fromMap(wire(lastOutcome: outcome));
      expect(status.summary, isNotEmpty, reason: outcome);
      expect(status.summary, isNot(contains(outcome)), reason: outcome);
    }
  });

  test('each outcome gets its own sentence, not the same one twice', () {
    final sentences = {
      for (final outcome in outcomes)
        outcome: ScreenReadingStatus.fromMap(wire(lastOutcome: outcome))
            .summary,
    };

    expect(sentences.values.toSet(), hasLength(outcomes.length));
  });

  test('an outcome from a newer version still says something', () {
    final status = ScreenReadingStatus.fromMap(wire(lastOutcome: 'who_knows'));

    expect(status.summary, isNotEmpty);
    expect(status.summary, isNot(contains('who_knows')));
  });

  test('a reader that has never run degrades instead of throwing', () {
    final status = ScreenReadingStatus.fromMap(const <Object?, Object?>{});

    expect(status.connected, isFalse);
    expect(status.allowlist, isEmpty);
    expect(status.scanCount, 0);
    expect(status.lastText, isNull);
    expect(status.hasScanned, isFalse);
    expect(status.summary, contains('No scan since'));
  });

  test('wrong-typed fields read as empty, not as a crash', () {
    final status = ScreenReadingStatus.fromMap(
      wire(scanCount: 'three', allowlist: 'com.whatsapp', rowCount: null),
    );

    expect(status.scanCount, 0);
    expect(status.allowlist, isEmpty);
    expect(status.rowCount, 0);
  });

  testWidgets('the card names the failure instead of saying it is broken', (
    tester,
  ) async {
    const channel = MethodChannel(AppConstants.channelName);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'screenReadingStatus') return null;
      return wire(scanCount: 12, rowCount: 0, lastOutcome: 'no_rows');
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ScreenReadingStatusCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scans: 12'), findsOneWidget);
    expect(find.textContaining('no row in it looked readable'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('a service that is not running says so first', (tester) async {
    const channel = MethodChannel(AppConstants.channelName);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'screenReadingStatus') return null;
      return wire(connected: false, enabledByUser: false);
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ScreenReadingStatusCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Service: not running'), findsOneWidget);
    expect(find.text('Switch: off'), findsOneWidget);
  });
}
