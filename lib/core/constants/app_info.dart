/// What this build is, in one place.
///
/// The app has no `package_info_plus` dependency on purpose: a settings screen
/// that reads its own version from the platform is one more thing that can be
/// wrong on a build someone else made. These constants are shipped in the
/// binary, and `test/app_info_test.dart` fails when they drift from
/// `pubspec.yaml` - so "which version are you running?" has one answer, and CI
/// is what keeps it true.
class AppInfo {
  AppInfo._();

  /// The product name. Not translated: it is a name, not a sentence.
  static const String name = 'ReplyMate AI';

  /// Must equal the `version:` field in pubspec.yaml, before the `+`.
  static const String version = '1.5.2';

  /// Must equal the build number after the `+` in pubspec.yaml.
  static const String buildNumber = '7';

  /// What a user reads on the About screen and quotes in a bug report.
  static const String versionLabel = '$version+$buildNumber';

  /// The repository this build came from. Shown as selectable text rather than
  /// a button: the app has no url_launcher, and a fake link is worse than a
  /// string a user can copy.
  static const String sourceUrl = 'https://github.com/Keshab1997/ReplyMate-AI';
}
