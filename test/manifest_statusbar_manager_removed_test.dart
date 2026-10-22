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

// docs/TODO.md T-224 (audit P1-01): `awesome_notifications` declares a
// service, `StatusBarManager`, that is exported and whose constructor path
// dereferences a null Context when the system instantiates it. Any app - or
// `adb shell am start-service` - can therefore crash this process, and with
// it a ringing alarm (device-verified 2026-10-23: the ring ended 6 s after
// the call). The app never starts it itself, so the merged manifest drops it.

void main() {
  test('the merged manifest removes awesome_notifications\' exported '
      'StatusBarManager service', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final decl = RegExp(
      r'<service[^>]*android:name="me\.carda\.awesome_notifications\.core\.managers\.StatusBarManager"[^>]*>',
      dotAll: true,
    ).firstMatch(manifest)?.group(0);
    expect(decl, isNotNull, reason: 'the removal entry is in the manifest');
    expect(decl, contains('tools:node="remove"'));
  });
}
