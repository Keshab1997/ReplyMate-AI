import '../../../core/constants/reply_options.dart';

/// A conservative, on-device detector for the three reply languages.
///
/// Script detection is reliable for Bengali and Devanagari. Latin-script chats
/// are ambiguous (English, Banglish and Hinglish share an alphabet), so those
/// are only classified when a few language-specific words agree; uncertainty
/// returns null and leaves the user's chosen default alone.
class ReplyLanguageDetector {
  ReplyLanguageDetector._();

  static ReplyLanguage? detect(String text) {
    var bengali = 0;
    var devanagari = 0;
    var latin = 0;
    for (final rune in text.runes) {
      if (rune >= 0x0980 && rune <= 0x09FF) bengali++;
      if (rune >= 0x0900 && rune <= 0x097F) devanagari++;
      if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        latin++;
      }
    }

    final scriptTotal = bengali + devanagari + latin;
    if (scriptTotal == 0) return null;
    // A few characters in a quoted name or mixed-language sentence should not
    // override the user's preference. Require both a small absolute count and
    // a meaningful share of the letters.
    if (bengali >= 2 && bengali / scriptTotal >= 0.20 && bengali > devanagari) {
      return ReplyLanguage.bengali;
    }
    if (devanagari >= 2 &&
        devanagari / scriptTotal >= 0.20 &&
        devanagari > bengali) {
      return ReplyLanguage.hindi;
    }
    if (latin == 0 || latin / scriptTotal < 0.55) return null;

    final words = RegExp(r'[a-z]+')
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .toSet();
    final bengaliScore = _score(words, _romanizedBengali);
    final hindiScore = _score(words, _romanizedHindi);
    final englishScore = _score(words, _english);
    if (englishScore == 1 && words.any(_strongEnglish.contains)) {
      return ReplyLanguage.english;
    }
    final best = [
      bengaliScore,
      hindiScore,
      englishScore,
    ].reduce((a, b) => a > b ? a : b);
    if (best < 2) return null;
    final winners = [
      if (bengaliScore == best) ReplyLanguage.bengali,
      if (hindiScore == best) ReplyLanguage.hindi,
      if (englishScore == best) ReplyLanguage.english,
    ];
    return winners.length == 1 ? winners.single : null;
  }

  static int _score(Set<String> words, Set<String> vocabulary) =>
      words.intersection(vocabulary).length;

  static const Set<String> _romanizedBengali = {
    'ami',
    'tumi',
    'apni',
    'amra',
    'tomar',
    'amar',
    'bhalo',
    'valo',
    'achi',
    'acho',
    'achho',
    'kemon',
    'kothay',
    'keno',
    'dhonnobad',
    'bolchi',
    'asbo',
    'jabo',
    'korbo',
    'hobe',
    'na',
    'hya',
    'hoyechhe',
    'ki',
  };

  static const Set<String> _romanizedHindi = {
    'main',
    'tum',
    'aap',
    'hum',
    'mera',
    'meri',
    'kaise',
    'kaisa',
    'hain',
    'hoon',
    'hai',
    'nahi',
    'nahin',
    'dhanyavad',
    'shukriya',
    'karunga',
    'aaoge',
    'jaunga',
    'kya',
    'kyun',
    'haan',
    'batao',
  };

  static const Set<String> _strongEnglish = {
    'thanks',
    'thank',
    'please',
    'hello',
    'tomorrow',
    'today',
    'where',
    'when',
    'why',
    'who',
    'what',
    'could',
    'would',
    'sorry',
  };

  static const Set<String> _english = {
    'the',
    'you',
    'your',
    'are',
    'is',
    'was',
    'were',
    'what',
    'when',
    'where',
    'who',
    'why',
    'how',
    'please',
    'thanks',
    'thank',
    'with',
    'for',
    'have',
    'has',
    'can',
    'could',
    'would',
    'will',
    'tomorrow',
    'today',
    'meeting',
    'hello',
    'hi',
    'sorry',
    'hey',
    'good',
    'need',
    'want',
    'from',
    'this',
    'that',
    'just',
  };
}
