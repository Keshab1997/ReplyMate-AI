import 'package:hive_flutter/hive_flutter.dart';

/// Local count of AI generation attempts made today.
///
/// This is informational only: it does not cap calls and is not a provider
/// billing meter. It stays per-device, so clearing app data resets the count.
class AiUsageSnapshot {
  const AiUsageSnapshot({required this.used, required this.day});

  final int used;

  /// Local calendar day the count belongs to, as `yyyy-mm-dd`.
  final String day;
}

class AiUsageTracker {
  AiUsageTracker({this.box, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  // Keep the existing box name so previously stored counts survive the update.
  static const String boxName = 'ai_budget';
  static const String _usedKey = 'used';
  static const String _dayKey = 'day';

  final Box<dynamic>? box;
  final DateTime Function() _now;

  static Future<Box<dynamic>> openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static String dayKeyFor(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  /// Today's count. Yesterday's value reads as zero without a write.
  AiUsageSnapshot snapshot() {
    final today = dayKeyFor(_now());
    final storedDay = box?.get(_dayKey) as String?;
    final used = storedDay == today ? (box?.get(_usedKey) as int? ?? 0) : 0;
    return AiUsageSnapshot(used: used, day: today);
  }

  /// Records one uncached generation attempt. Counter failures never block AI.
  Future<void> recordAttempt() async {
    try {
      final current = snapshot();
      await box?.put(_dayKey, current.day);
      await box?.put(_usedKey, current.used + 1);
    } catch (_) {
      // Informational tracking must never stop generation.
    }
  }
}
