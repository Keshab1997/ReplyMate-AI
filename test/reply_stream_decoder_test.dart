import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/features/reply/data/reply_stream_decoder.dart';
import 'package:replymate/features/reply/data/stream_deltas.dart';

void main() {
  group('SSE deltas', () {
    test('reads the OpenAI content field', () {
      expect(
        StreamDeltas.openAi(
          'data: {"choices":[{"delta":{"content":"হ্যালো"}}]}',
        ),
        'হ্যালো',
      );
    });

    test('ignores role announcements, keepalives and the DONE sentinel', () {
      expect(
        StreamDeltas.openAi(
          'data: {"choices":[{"delta":{"role":"assistant"}}]}',
        ),
        isNull,
      );
      expect(StreamDeltas.openAi(': keepalive'), isNull);
      expect(StreamDeltas.openAi('data: [DONE]'), isNull);
      expect(StreamDeltas.openAi(''), isNull);
    });

    test('never shows reasoning text as a reply', () {
      // Providers stream the model's scratchpad under its own key. Putting it
      // in the user's message would be putting the wrong words in their mouth.
      expect(
        StreamDeltas.openAi(
          'data: {"choices":[{"delta":{"reasoning":"let me think"}}]}',
        ),
        isNull,
      );
    });

    test('reads Gemini parts', () {
      expect(
        StreamDeltas.gemini(
          'data: {"candidates":[{"content":{"parts":[{"text":"শুভ"}]}}]}',
        ),
        'শুভ',
      );
    });

    test('a half-written line is skipped, not guessed at', () {
      expect(StreamDeltas.openAi('data: {"choices":[{"delta":{"cont'), isNull);
    });
  });

  group('the decoder keeps a preview apart from an answer', () {
    /// Feeds the JSON envelope one character at a time, the way a slow provider
    /// does, and records every preview seen.
    List<List<String>> dribble(String json, {int chunk = 1}) {
      final decoder = ReplyStreamDecoder();
      final seen = <List<String>>[];
      for (var i = 0; i < json.length; i += chunk) {
        final end = (i + chunk).clamp(0, json.length);
        if (decoder.add(json.substring(i, end))) {
          seen.add(decoder.partial);
        }
      }
      return seen;
    }

    test('previews only complete strings, and never mid-word', () {
      const json = '{"replies":["প্রথম উত্তর","দ্বিতীয় উত্তর"]}';
      final seen = dribble(json);

      expect(seen, isNotEmpty);
      expect(seen.last, ['প্রথম উত্তর', 'দ্বিতীয় উত্তর']);
      // Every preview is a prefix of the real answer: no half-written string is
      // ever shown, so the text cannot flicker as it reflows.
      for (final preview in seen) {
        expect(preview, seen.last.sublist(0, preview.length));
      }
      expect(seen.first, ['প্রথম উত্তর']);
    });

    test('is not complete until the envelope closes', () {
      final decoder = ReplyStreamDecoder();
      decoder.add('{"replies":["একটি উত্তর"');
      expect(decoder.partial, ['একটি উত্তর']);
      expect(decoder.isComplete, isFalse, reason: 'no closing brace yet');

      decoder.add(']}');
      expect(decoder.isComplete, isTrue);
    });

    test('a truncated stream never becomes complete', () {
      final decoder = ReplyStreamDecoder();
      decoder.add('{"replies":["একটি উত্তর","দ্বিতীয় উ');
      expect(decoder.partial, ['একটি উত্তর']);
      // The point of the whole class: the user saw a preview, and the decoder
      // still refuses to call it an answer.
      expect(decoder.isComplete, isFalse);
    });

    test('double-encoded content still previews and still finishes', () {
      final inner = jsonEncode({
        'replies': ['এক'],
      });
      final decoder = ReplyStreamDecoder();
      decoder.add(
        jsonEncode({
          'replies': [inner],
        }),
      );
      expect(decoder.isComplete, isTrue);
      expect(decoder.partial, hasLength(1));
    });

    test('a non-JSON answer previews nothing', () {
      final decoder = ReplyStreamDecoder();
      expect(decoder.add('সরাসরি লেখা উত্তর'), isFalse);
      expect(decoder.partial, isEmpty);
      expect(decoder.isComplete, isFalse);
    });

    test('add() reports no change when the text did not move the preview', () {
      final decoder = ReplyStreamDecoder();
      expect(decoder.add('{"replies":['), isFalse);
      expect(decoder.add('"a"'), isTrue);
      expect(decoder.add(''), isFalse);
    });
  });
}
