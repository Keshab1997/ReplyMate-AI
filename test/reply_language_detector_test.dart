import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/reply_options.dart';
import 'package:replymate/features/reply/data/reply_language_detector.dart';

void main() {
  test('recognises Bengali and Hindi scripts on device', () {
    expect(
      ReplyLanguageDetector.detect('তুমি কেমন আছো?'),
      ReplyLanguage.bengali,
    );
    expect(ReplyLanguageDetector.detect('आप कैसे हैं?'), ReplyLanguage.hindi);
  });

  test('recognises clear English and transliterated South Asian messages', () {
    expect(
      ReplyLanguageDetector.detect('Can we meet tomorrow please?'),
      ReplyLanguage.english,
    );
    expect(ReplyLanguageDetector.detect('Thanks!'), ReplyLanguage.english);
    expect(
      ReplyLanguageDetector.detect('Ami bhalo achi'),
      ReplyLanguage.bengali,
    );
    expect(ReplyLanguageDetector.detect('Aap kaise ho'), ReplyLanguage.hindi);
  });

  test('keeps the user default when text is too short or ambiguous', () {
    expect(ReplyLanguageDetector.detect('ok'), isNull);
    expect(ReplyLanguageDetector.detect('kal meeting'), isNull);
    expect(ReplyLanguageDetector.detect('12345'), isNull);
  });
}
