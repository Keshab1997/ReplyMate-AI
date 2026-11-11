import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_selection/providers/selected_apps_provider.dart';
import '../../notifications/models/captured_notification.dart';
import '../data/conversation_memory_store.dart';
import '../domain/conversation_memory.dart';
import '../domain/memory_recorder.dart';

/// The store, one per app run. A single instance matters: two stores over one
/// box would each think they own the contact cap.
final Provider<ConversationMemoryStore> conversationMemoryStoreProvider =
    Provider<ConversationMemoryStore>((ref) => ConversationMemoryStore());

final Provider<MemoryRecorder> memoryRecorderProvider =
    Provider<MemoryRecorder>((ref) => const MemoryRecorder());

/// The master switch of docs/CONVERSATION_MEMORY.md — off until the user says
/// otherwise, and turning it off deletes what it stored.
///
/// Default `false` is not a placeholder: it is the feature's first wall. Until
/// the user reads what it does and turns it on, this app writes no message text
/// anywhere.
final NotifierProvider<ConversationMemorySwitch, bool>
conversationMemoryEnabledProvider =
    NotifierProvider<ConversationMemorySwitch, bool>(
      ConversationMemorySwitch.new,
    );

class ConversationMemorySwitch extends Notifier<bool> {
  static const String prefsKey = 'conversation_memory_enabled';

  bool _alive = true;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_alive) return;
      state = prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      // Unreadable preferences mean "off", the safe direction to fail in.
      if (_alive) state = false;
    }
  }

  /// Turning it off is destructive on purpose: "off" means the stored
  /// conversations are gone, not frozen. A user who switches this off because
  /// they were uneasy is owed exactly that.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, enabled);
    } catch (_) {
      // The in-memory switch still governs this run.
    }
    if (!enabled) {
      await ref.read(conversationMemoryStoreProvider).forgetAll();
    }
  }
}

/// The one place the app writes conversation memory.
///
/// Reading and writing are deliberately separate: [windowFor] never writes, and
/// [rememberCapture] never answers. A read that quietly wrote would make the
/// Settings list and the device checklist both lie about when things are
/// stored.
class ConversationMemoryController {
  ConversationMemoryController(this._ref);

  final Ref _ref;

  bool get isEnabled => _ref.read(conversationMemoryEnabledProvider);

  ConversationMemoryStore get _store =>
      _ref.read(conversationMemoryStoreProvider);

  MemoryRecorder get _recorder => _ref.read(memoryRecorderProvider);

  Set<String> get _allowlist => _ref.read(selectedAppsProvider).toSet();

  /// The contact a capture belongs to, or null when it cannot be filed - no
  /// sender name, no package. A capture that cannot be filed is not remembered:
  /// one nameless bucket holding everyone's conversations is worse than no
  /// memory at all.
  ConversationKey? keyFor(CapturedNotification capture) =>
      ConversationKey.tryOf(
        packageName: capture.packageName,
        contactName: capture.title,
      );

  /// What the app already knows about this conversation, for the prompt.
  ///
  /// Null means "no memory applies here" - the switch is off, the app is not
  /// allowlisted, or the contact cannot be filed. Callers fall back to whatever
  /// the capture itself carried, which is exactly what the app did before this
  /// feature existed.
  Future<ConversationMemory?> windowFor(CapturedNotification capture) async {
    if (!isEnabled) return null;
    final key = keyFor(capture);
    if (key == null) return null;
    if (!_allowlist.contains(capture.packageName)) return null;
    return _store.read(key);
  }

  /// Stores the incoming message, then returns the window *including* it.
  ///
  /// Called where a reply surface opens, not on every notification: a message
  /// the user never answered is not a conversation the user asked this app to
  /// remember (docs/CONVERSATION_MEMORY.md §5).
  Future<ConversationMemory?> rememberCapture(
    CapturedNotification capture, {
    DateTime? now,
  }) async {
    if (!isEnabled) return null;
    final key = keyFor(capture);
    if (key == null) return null;

    final at = now ?? DateTime.now();
    final existing = await _store.read(key, now: at);
    final lines = _recorder.linesForCapture(
      capture,
      allowedPackages: _allowlist,
      now: at,
    );
    final next = _recorder.apply(existing, lines, now: at);
    if (identical(next, existing)) {
      // Nothing was allowed in (allowlist, redaction, empty text). Do not write;
      // an unanswered "nothing happened" must not look like a change.
      return existing;
    }
    await _store.save(next, now: at);
    return next;
  }

  /// Records a reply the user accepted - the one reliable source of `me` lines
  /// (§8), and the whole basis of the voice half of this feature.
  Future<void> rememberAcceptedReply({
    required CapturedNotification capture,
    required String text,
    DateTime? now,
  }) async {
    if (!isEnabled) return;
    final key = keyFor(capture);
    if (key == null) return;
    if (!_allowlist.contains(capture.packageName)) return;

    final at = now ?? DateTime.now();
    final existing = await _store.read(key, now: at);
    final line = _recorder.lineForAcceptedReply(text, now: at);
    final next = _recorder.apply(
      existing,
      line == null ? const <MemoryLine>[] : <MemoryLine>[line],
      now: at,
    );
    if (identical(next, existing)) return;
    await _store.save(next, now: at);
  }

  Future<List<ConversationKey>> contacts() => _store.contacts();

  Future<void> forget(ConversationKey key) => _store.forget(key);

  Future<void> forgetAll() => _store.forgetAll();
}

final Provider<ConversationMemoryController>
conversationMemoryControllerProvider = Provider<ConversationMemoryController>(
  ConversationMemoryController.new,
);
