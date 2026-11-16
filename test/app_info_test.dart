import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:replymate/core/constants/app_info.dart';

void main() {
  test('the displayed version comes from installed package metadata', () async {
    final container = ProviderContainer(
      overrides: [
        packageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'ReplyMate AI',
            packageName: 'com.example.replymate',
            version: '9.8.7',
            buildNumber: '65',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(appVersionLabelProvider.future), '9.8.7+65');
  });

  test('the product identity is stable and points at this project', () {
    expect(AppInfo.name, 'ReplyMate AI');
    expect(AppInfo.sourceUrl, startsWith('https://github.com/Keshab1997/'));
    expect(AppInfo.sourceUrl, isNot(contains('example')));
  });
}
