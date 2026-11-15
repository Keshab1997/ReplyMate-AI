import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:replymate/core/constants/app_info.dart';

/// The About screen shows a version. A version that is only *typed* into Dart
/// is a version that is wrong within one release, and nobody notices, because
/// the wrong number looks exactly like the right one.
///
/// So the number has one source of truth - `pubspec.yaml` - and this test is
/// the wall around it: bump the pubspec without bumping [AppInfo] and CI goes
/// red, instead of shipping a build that misreports itself.
void main() {
  test('the version in the app is the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(
      match,
      isNotNull,
      reason:
          'pubspec.yaml has no `version: x.y.z+n` line, so there is nothing '
          'for the About screen to tell the truth about.',
    );
    expect(
      AppInfo.version,
      match!.group(1),
      reason:
          'AppInfo.version is stale - pubspec.yaml says ${match.group(1)}. '
          'Bump lib/core/constants/app_info.dart with the release.',
    );
    expect(
      AppInfo.buildNumber,
      match.group(2),
      reason:
          'AppInfo.buildNumber is stale - pubspec.yaml says +${match.group(2)}.',
    );
  });

  test('the label a user quotes is both parts, joined once', () {
    expect(AppInfo.versionLabel, '${AppInfo.version}+${AppInfo.buildNumber}');
    expect(
      RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(AppInfo.versionLabel),
      isTrue,
    );
  });

  test('the source url points at this project, not at a placeholder', () {
    expect(AppInfo.sourceUrl, startsWith('https://github.com/Keshab1997/'));
    expect(AppInfo.sourceUrl, isNot(contains('example')));
  });
}
