import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-48: recommended GPLv3 practice is a copyright/licence
// notice at the top of every source file, so a file copied out of the
// repository doesn't lose its licence trace. A source-reading test, not a
// runtime one - there is no behaviour to exercise, only a convention to
// keep from silently regressing (a new file added without the header, or
// an existing one stripped during an edit).
void main() {
  test('every lib/ source file carries the GPLv3 licence header', () {
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (!content.contains('This file is part of WakeyWakey.') ||
          !content.contains('GNU General Public License')) {
        missing.add(entity.path);
      }
    }

    expect(missing, isEmpty,
        reason: 'missing the GPLv3 licence header: ${missing.join(', ')}');
  });
}
