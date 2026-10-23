// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The project is GPL-3.0-or-later (maintainer decision 2026-10-23): every source
// header already says "either version 3 of the License, or (at your option)
// any later version", and README, the About page, the store listing and the
// F-Droid recipe draft have to say the same instead of a bare "v3.0" - F-Droid
// takes the licence field from the recipe, and a mismatch is a question a
// reviewer asks.

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('README names the licence as GPL-3.0-or-later', () {
    final readme = _read('README.md');
    expect(readme, contains('GPL-3.0-or-later'));
    expect(readme, isNot(contains('License v3.0 - see')));
  });

  test('the About page\'s legal line says "or any later version"', () {
    final about = _read('lib/screens/settings/page_aboutpage.dart');
    expect(about, contains('or any later version'));
    expect(about, isNot(contains('General Public License v3.0')));
  });

  test('the store listing and the recipe draft agree', () {
    expect(_read('fastlane/metadata/android/en-US/full_description.txt'),
        contains('GPL v3 or later'));
    expect(_read('docs/fdroid-recipe-draft.yml'),
        contains('License: GPL-3.0-or-later'));
  });

  test('every Dart source header grants "any later version"', () {
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      expect(_read(f.path), contains('(at your option) any later version'), reason: f.path);
    }
  });
}
