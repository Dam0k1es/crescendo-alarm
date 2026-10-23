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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// F-Droid reads the store listing from fastlane/metadata/android/<locale>/
// in the repository (docs/TODO.md, F-Droid readiness). Its limits: short
// description 80 characters, full description 4000, a changelog per
// versionCode of 500. This keeps the listing complete and inside them, and
// keeps the changelog in step with the version in pubspec.yaml - a release
// bump without a changelog file would ship an empty "what's new".

const _dir = 'fastlane/metadata/android/en-US';

String _text(String name) => File('$_dir/$name').readAsStringSync();

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes.sublist(16, 24)));
  return (width: data.getUint32(0), height: data.getUint32(4));
}

void main() {
  test('title, short and full description exist and respect the limits', () {
    expect(_text('title.txt').trim(), 'Crescendo Alarm');
    expect(_text('short_description.txt').trim().length, inInclusiveRange(1, 80));
    expect(_text('full_description.txt').trim().length, inInclusiveRange(1, 4000));
  });

  test('there is a changelog for the versionCode in pubspec.yaml, within 500 '
      'characters', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final code = RegExp(r'^version: [^+\n]+\+(\d+)$', multiLine: true)
        .firstMatch(pubspec)!
        .group(1)!;
    final changelog = File('$_dir/changelogs/$code.txt');
    expect(changelog.existsSync(), isTrue,
        reason: 'fastlane changelog for versionCode $code is missing');
    expect(changelog.readAsStringSync().trim().length, inInclusiveRange(1, 500));
  });

  test('the icon is a 512x512 PNG', () {
    final size = _pngSize('$_dir/images/icon.png');
    expect((size.width, size.height), (512, 512));
  });

  test('there are phone screenshots, and every one is a portrait PNG', () {
    final shots = Directory('$_dir/images/phoneScreenshots')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    expect(shots, isNotEmpty);
    for (final shot in shots) {
      final size = _pngSize(shot.path);
      expect(size.height, greaterThan(size.width), reason: shot.path);
    }
  });

  test('the listing is honest about the limits it must not hide', () {
    final full = _text('full_description.txt');
    for (final phrase in [
      '60 minutes',
      'Force-stopping',
      'time zone',
      'Display over other apps',
      'second alarm',
      'no internet permission',
    ]) {
      expect(full, contains(phrase));
    }
  });
}
