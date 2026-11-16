import 'dart:convert';

/// Pure helpers for reading a streamed provider response.
///
/// Everything here takes a single SSE `data:` line and returns the text it
/// carries, or null when the line is a keepalive, a role announcement, or a
/// `[DONE]` sentinel. Keeping the parsing pure is deliberate: the transport
/// (an HTTP stream) cannot be exercised in a widget test, but these functions
/// can, and they are where the dialects actually differ.
class StreamDeltas {
  const StreamDeltas._();

  /// `{choices: [{delta: {content: "…"}}]}`, plus the `reasoning` siblings that
  /// some providers stream instead. Reasoning text is never shown as a reply -
  /// it is not the answer, and treating it as one would put the model's private
  /// scratchpad in the user's message.
  static String? openAi(String line) {
    final payload = _payloadOf(line);
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final delta = first['delta'] ?? first['message'];
      if (delta is! Map) return null;
      final content = delta['content'];
      if (content is String) return content;
      // Content as a list of parts (OpenAI vision/multimodal shape).
      if (content is List) {
        final buffer = StringBuffer();
        for (final part in content) {
          if (part is Map && part['text'] is String) {
            buffer.write(part['text'] as String);
          }
        }
        final text = buffer.toString();
        return text.isEmpty ? null : text;
      }
      return null;
    } catch (_) {
      // A partial or non-JSON line: nothing to show, nothing to report.
      return null;
    }
  }

  /// `{candidates: [{content: {parts: [{text: "…"}]}}]}`.
  static String? gemini(String line) {
    final payload = _payloadOf(line);
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map) return null;
      final content = first['content'];
      if (content is! Map) return null;
      final parts = content['parts'];
      if (parts is! List) return null;
      final buffer = StringBuffer();
      for (final part in parts) {
        if (part is Map && part['text'] is String) {
          buffer.write(part['text'] as String);
        }
      }
      final text = buffer.toString();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// The JSON after `data:` on an SSE line, or the line itself when a provider
  /// ignored SSE and sent bare JSON. Null for `[DONE]`, comments and blank
  /// lines.
  static String? _payloadOf(String line) {
    var text = line.trim();
    if (text.isEmpty || text.startsWith(':')) return null;
    if (text.startsWith('data:')) text = text.substring(5).trim();
    if (text.isEmpty || text == '[DONE]') return null;
    return text;
  }
}
