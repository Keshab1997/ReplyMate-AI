import 'dart:convert';

/// Turns a stream of provider text into the one thing the screen may show
/// while an answer is still arriving.
///
/// The reply contract is `{"replies": ["…", "…"]}`, so the middle of the stream
/// is *not* something that can be shown as an answer: it may be half a JSON
/// key, half a word, or a key that is about to be followed by a quote. This
/// decoder therefore keeps two things apart:
///
/// * [partial] — a best-effort preview of the reply strings seen so far, only
///   ever produced from **complete** JSON string values inside the `replies`
///   array. It is allowed to grow, and is allowed to be wrong at the end,
///   because nothing may be shown as a finished answer until [isComplete].
/// * [isComplete] — true only when the envelope closed and the array decoded.
///
/// The screen renders [partial] under a "writing…" state and replaces it with
/// the parsed result (or an honest failure) when the stream ends. A truncated
/// stream never turns into a visible answer: that is the dishonesty this
/// class exists to prevent.
class ReplyStreamDecoder {
  ReplyStreamDecoder({this.maxReplies = 3});

  /// How many reply strings to preview; matches the request's `count` ceiling.
  final int maxReplies;

  final StringBuffer _raw = StringBuffer();
  List<String> _partial = const <String>[];

  /// Everything received so far, verbatim. The real parser runs on this, so a
  /// preview that guessed wrong cannot corrupt the final answer.
  String get raw => _raw.toString();

  /// Reply strings completed so far. Empty until a first string closes.
  List<String> get partial => List<String>.unmodifiable(_partial);

  /// Whether the stream has produced a full, decodable envelope. Once this is
  /// true the caller should parse [raw] properly and stop treating [partial] as
  /// a preview.
  bool get isComplete {
    if (!_looksFinished) return false;
    try {
      final decoded = jsonDecode(_envelopeOf(_raw.toString()) ?? '');
      return decoded is Map && decoded['replies'] is List;
    } catch (_) {
      return false;
    }
  }

  bool _looksFinished = false;

  /// Feeds one chunk of streamed text. Returns true when [partial] changed, so
  /// the UI only rebuilds on real progress.
  bool add(String chunk) {
    if (chunk.isEmpty) return false;
    _raw.write(chunk);
    if (_buffered().trim().endsWith('}')) _looksFinished = true;

    final next = _previewFrom(_raw.toString());
    if (_sameList(next, _partial)) return false;
    _partial = next;
    return true;
  }

  String _buffered() => _raw.toString();

  bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Locates the outermost `{ … }` in the buffer, ignoring braces inside
  /// strings — the same rule the plain parser uses, so a Bengali reply full of
  /// punctuation cannot confuse it.
  static String? _envelopeOf(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = !inString;
      } else if (!inString && char == '{') {
        depth++;
      } else if (!inString && char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Complete reply strings inside the `replies` array. A string that has not
  /// closed yet is skipped rather than shown half-written: a preview that
  /// re-flows a word as it arrives looks like a bug, not like progress.
  List<String> _previewFrom(String text) {
    final property = RegExp(
      r'''["']replies["']\s*:\s*\[|["']replies["']\s*:''',
      caseSensitive: false,
    ).firstMatch(text);
    if (property == null) return const <String>[];

    final found = <String>[];
    var index = property.end;
    while (index < text.length && found.length < maxReplies) {
      while (index < text.length &&
          (text[index].trim().isEmpty || text[index] == ',')) {
        index++;
      }
      if (index >= text.length || text[index] == ']' || text[index] == '}') {
        break;
      }
      if (text[index] != '"' && text[index] != "'") break;

      final quote = text[index];
      final start = index++;
      var escaped = false;
      var closed = false;
      while (index < text.length) {
        final char = text[index];
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == quote) {
          index++;
          closed = true;
          final slice = text.substring(start, index);
          try {
            final value = jsonDecode(
              quote == '"'
                  ? slice
                  : '"${slice.substring(1, slice.length - 1)}"',
            );
            if (value is String && value.trim().isNotEmpty) {
              found.add(value.trim());
            }
          } catch (_) {
            // A half-written escape sequence; it will be complete next chunk.
          }
          break;
        }
        index++;
      }
      if (!closed) break;
    }
    return found;
  }
}
