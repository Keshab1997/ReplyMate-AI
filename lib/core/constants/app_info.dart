import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Product identity and metadata for the installed app.
///
/// Version comes from the built platform package, which Flutter derives from
/// `pubspec.yaml` (including build-name/build-number overrides). This keeps the
/// About screen accurate without a second version string to update by hand.
class AppInfo {
  AppInfo._();

  /// The product name. Not translated: it is a name, not a sentence.
  static const String name = 'ReplyMate AI';

  /// The repository this build came from. Shown as selectable text rather than
  /// a button: the app has no url_launcher, and a fake link is worse than a
  /// string a user can copy.
  static const String sourceUrl = 'https://github.com/Keshab1997/ReplyMate-AI';
}

/// Platform package metadata; Flutter's build sets its version from pubspec.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Version string shown to users and included in bug reports.
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  final packageInfo = await ref.watch(packageInfoProvider.future);
  return '${packageInfo.version}+${packageInfo.buildNumber}';
});
