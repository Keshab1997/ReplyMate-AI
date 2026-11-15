import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../tool/screenshots/shot_registry.dart';

/// The screenshot tool lives outside `test/`, so nothing would notice if a
/// screen it names were deleted or renamed - the failure would arrive when
/// somebody next ran it, on their own time. This file is the wall: the registry
/// has to compile against the app and name every shot uniquely.
///
/// It deliberately does *not* render anything. Rendering is a human's decision
/// (`python3 tool/screenshots.py`), not something CI pays for.
void main() {
  test('every registered shot still builds a widget', () {
    for (final shot in shots) {
      expect(
        shot.build(),
        isA<Widget>(),
        reason: 'shot "${shot.name}" no longer builds',
      );
    }
  });

  test('shot names are unique and safe as file names', () {
    final names = shots.map((shot) => shot.name).toList();
    expect(names.toSet().length, names.length, reason: 'duplicate shot name');
    for (final name in names) {
      expect(
        RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name),
        isTrue,
        reason:
            '"$name" is not kebab-case, so it is awkward to type and to '
            'reference from a script',
      );
    }
  });

  test('the shots that catch layout breakage are still registered', () {
    // A tool that only photographs the comfortable phone cannot answer the
    // question it exists for. These three are the awkward cases, by name.
    final names = shots.map((shot) => shot.name).toSet();
    expect(names.contains('settings-hub-narrow'), isTrue);
    expect(names.contains('settings-reply-bigtext'), isTrue);
    expect(names.contains('settings-hub-light'), isTrue);
  });

  test('--shot selects by name, and an empty filter means everything', () {
    final first = shots.first.name;
    expect(selectShots(first).map((shot) => shot.name), <String>[first]);
    expect(selectShots('').length, shots.length);
    expect(selectShots('  ').length, shots.length);
    expect(selectShots('does-not-exist'), isEmpty);
  });
}
