import 'package:hive_flutter/hive_flutter.dart';

/// The state of today's AI allowance, as the UI should show it.
class AiBudgetSnapshot {
  const AiBudgetSnapshot({
    required this.used,
    required this.limit,
    required this.day,
  });

  final int used;
  final int limit;

  /// Local calendar day the count belongs to, as `yyyy-mm-dd`. A new day is a
  /// new allowance, which is why the day is stored rather than inferred.
  final String day;

  int get remaining => (limit - used).clamp(0, limit);
  bool get exhausted => used >= limit;
  double get fraction => limit == 0 ? 1 : (used / limit).clamp(0, 1);
}

/// A per-device daily ceiling on paid AI calls.
///
/// `ApiKeyManager` protects against *dead* keys; nothing protected against
/// *usage*. That is the difference between a free app and a surprise invoice on
/// someone else's provider account, so this counter exists even though it is
/// the least interesting code in the feature: no budget, no "free".
///
/// Deliberate limits of the design, stated so they are not mistaken for
/// guarantees:
/// - **Per device, not per account.** Clearing app data resets it. It is a
///   guard against a runaway loop or a boredom tap, not a billing system.
/// - **Counts calls that were made**, not tokens spent — tokens vary by
///   provider and model, and a counter that lies about its units is worse than
///   an honest count of requests.
/// - **Fails open.** If the counter cannot be read or written, the call is
///   allowed: a broken counter must never be the reason the app stops working.
class AiBudget {
  AiBudget({this.box, this.limit = defaultLimit, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// 50 paid generations a day is far more than a person needs and far less
  /// than a runaway loop spends before anyone notices.
  static const int defaultLimit = 50;

  static const String boxName = 'ai_budget';
  static const String _usedKey = 'used';
  static const String _dayKey = 'day';

  final Box<dynamic>? box;
  final int limit;
  final DateTime Function() _now;

  static Future<Box<dynamic>> openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static String dayKeyFor(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  /// Today's state. A stored count from an earlier day reads as zero without
  /// needing a write, so opening the app at midnight costs nothing.
  AiBudgetSnapshot snapshot() {
    final today = dayKeyFor(_now());
    final storedDay = box?.get(_dayKey) as String?;
    final used = storedDay == today ? (box?.get(_usedKey) as int? ?? 0) : 0;
    return AiBudgetSnapshot(used: used, limit: limit, day: today);
  }

  /// Whether a paid call may be made now.
  bool get canSpend => !snapshot().exhausted;

  /// Records one paid call. Called only after a call was actually attempted —
  /// counting a request the app refused to make would double-charge the user's
  /// allowance for nothing.
  Future<void> record() async {
    final current = snapshot();
    try {
      await box?.put(_dayKey, current.day);
      await box?.put(_usedKey, current.used + 1);
    } catch (_) {
      // Fails open on purpose: see the class comment.
    }
  }

  /// Resets today's count. Exposed so the limit state can offer "I know, use
  /// one more" instead of a dead end — a hard stop with no override is how
  /// users learn to reinstall an app.
  Future<void> forgetToday() async {
    try {
      await box?.delete(_usedKey);
    } catch (_) {}
  }
}
