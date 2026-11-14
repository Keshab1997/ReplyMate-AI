import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';

/// Explicitly saved, reusable reply text. Stored locally as user-authored
/// templates; incoming messages are never added here automatically.
final NotifierProvider<SavedRepliesNotifier, List<String>>
savedRepliesProvider = NotifierProvider<SavedRepliesNotifier, List<String>>(
  SavedRepliesNotifier.new,
);

class SavedRepliesNotifier extends Notifier<List<String>> {
  bool _alive = true;
  late Future<void> _ready;
  static const int maxSavedReplies = 20;

  @override
  List<String> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _ready = _load();
    return const <String>[];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_alive) return;
    final saved =
        prefs.getStringList(AppConstants.prefSavedReplies) ?? const <String>[];
    state = saved
        .map((reply) => reply.trim())
        .where((reply) => reply.isNotEmpty)
        .take(maxSavedReplies)
        .toList(growable: false);
  }

  Future<bool> add(String value) async {
    await _ready;
    final reply = value.trim();
    if (reply.isEmpty ||
        state.contains(reply) ||
        state.length >= maxSavedReplies) {
      return false;
    }
    final next = List<String>.unmodifiable([...state, reply]);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(AppConstants.prefSavedReplies, next);
    return true;
  }

  Future<void> remove(String reply) async {
    await _ready;
    final next = List<String>.unmodifiable(
      state.where((saved) => saved != reply),
    );
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(AppConstants.prefSavedReplies);
    } else {
      await prefs.setStringList(AppConstants.prefSavedReplies, next);
    }
  }

  Future<void> clear() async {
    await _ready;
    state = const <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefSavedReplies);
  }
}
