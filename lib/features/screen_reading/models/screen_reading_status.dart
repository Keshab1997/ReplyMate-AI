/// What the screen reader did the last time it looked at the screen.
/// "It reads nothing" is five different failures, and from outside the phone
/// they are impossible to tell apart: the window belonged to another app, no
/// message list was found, every row was rejected, or the newest message was
/// one the user had already sent. Each one has a different fix.
/// This is the difference between guessing and knowing, and Settings shows it -
/// so a problem can be named without adb on a laptop.
class ScreenReadingStatus {
  const ScreenReadingStatus({
    required this.connected,
    required this.enabledByUser,
    required this.allowlist,
    required this.scanCount,
    required this.lastScanAtMillis,
    required this.listCount,
    required this.rowCount,
    this.lastOutcome,
    this.lastPackage,
    this.lastText,
  });

  factory ScreenReadingStatus.fromMap(Map<Object?, Object?> map) {
    final rawAllowlist = map['allowlist'];
    return ScreenReadingStatus(
      connected: map['connected'] == true,
      enabledByUser: map['enabledByUser'] == true,
      allowlist: rawAllowlist is List
          ? <String>[
              for (final entry in rawAllowlist)
                if (entry is String) entry,
            ]
          : const <String>[],
      scanCount: _int(map['scanCount']),
      lastScanAtMillis: _int(map['lastScanAtMillis']),
      listCount: _int(map['listCount']),
      rowCount: _int(map['rowCount']),
      lastOutcome: map['lastOutcome'] as String?,
      lastPackage: map['lastPackage'] as String?,
      lastText: map['lastText'] as String?,
    );
  }

  static int _int(Object? value) => value is int ? value : 0;

  /// The service is alive in this process right now.
  final bool connected;

  /// The in-app switch is on. Android's grant and this switch are two things.
  final bool enabledByUser;

  /// The packages the user selected.
  final List<String> allowlist;

  /// How many times the reader has looked at a screen since install.
  final int scanCount;

  final int lastScanAtMillis;

  /// How many scrolling containers were on the screen.
  final int listCount;

  /// How many rows of the chosen list looked readable.
  final int rowCount;

  /// One of: `read`, `no_window`, `other_app`, `no_list`, `no_rows`,
  /// `no_message`, `outgoing`, `not_new`. Null before the first scan.
  final String? lastOutcome;

  final String? lastPackage;

  /// The first 200 characters of what was read, for the report only.
  final String? lastText;

  bool get hasScanned => lastOutcome != null;

  /// Whether the reader is doing its job.
  /// `outgoing` and `not_new` are not failures - they are the reader correctly
  /// deciding there is nothing to answer - so they must not be offered as
  /// something to fix. Null is not healthy either: a reader that has never
  /// scanned once is the situation most worth a button.
  bool get isHealthy =>
      lastOutcome == 'read' ||
      lastOutcome == 'not_new' ||
      lastOutcome == 'outgoing';

  /// Whether there is something the user can act on.
  /// Deliberately not true before the first scan: a reader that has never been
  /// given a screen is not broken, and pointing at Android's settings would be
  /// the wrong advice for somebody who simply has not opened a chat yet.
  bool get needsAttention => !connected || (hasScanned && !isHealthy);

  /// Plain language for the last scan. `no_rows` is not something a person can
  /// act on; "the list was there but no row looked readable" is.
  String get summary {
    switch (lastOutcome) {
      case 'read':
        return 'Read a message.';
      case 'no_window':
        return 'Nothing was in front to read.';
      case 'other_app':
        return 'The window in front belonged to another app.';
      case 'no_list':
        return 'No message list found on that screen.';
      case 'no_rows':
        return 'Found the list, but no row in it looked readable.';
      case 'no_message':
        return 'Rows were there, but none of them held a message.';
      case 'outgoing':
        return 'The newest message was one you sent.';
      case 'not_new':
        return 'Already seen, or you scrolled past it.';
      default:
        return 'No scan since the app was installed.';
    }
  }
}
