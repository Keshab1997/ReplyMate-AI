import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/l10n/app_strings.dart';

/// A backslash that reaches the screen is always a bug, and it is invisible in
/// review: `'...language,\\nwith you...'` looks exactly like an intended line
/// break in a diff, and the onboarding rendered the four characters `\n` in the
/// middle of its subtitle until someone photographed the screen.
///
/// Two guards: the source may not contain an escaped backslash-newline at all,
/// and the strings that are meant to wrap must carry a real newline.
void main() {
  test('no string literal spells out a backslash', () {
    final source = File('lib/core/l10n/app_strings.dart').readAsStringSync();
    expect(
      source,
      isNot(contains(r'\\n')),
      reason:
          'A literal backslash-n in a string renders as the characters "\\n". '
          'Use \'\\n\' for a real line break.',
    );
  });

  test('the onboarding subtitle wraps instead of showing an escape', () {
    for (final strings in <AppStrings>[
      const EnglishStrings(),
      const BengaliStrings(),
      const HindiStrings(),
    ]) {
      expect(strings.onboardingSubtitle, contains('\n'));
      expect(strings.onboardingSubtitle, isNot(contains(r'\')));
    }
  });
}
