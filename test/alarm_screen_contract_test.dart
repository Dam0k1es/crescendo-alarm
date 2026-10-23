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

// docs/TODO.md T-240: the alarm screen opening by itself spans Dart, Kotlin
// and the manifest, none of which can run the others in `flutter test`.
// Source-reading, the same shape as ring_timeout_contract_test.dart.

const _kotlinDir =
    'android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm';
String _read(String path) => File(path).readAsStringSync();

void main() {
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final launcher = _read('$_kotlinDir/RingScreenLauncher.kt');
  final access = _read('$_kotlinDir/AlarmScreenAccess.kt');
  final mainActivity = _read('$_kotlinDir/MainActivity.kt');
  final dart = _read('lib/utils/alarm_screen_access.dart');
  final script = _read('scripts/check_manifest_permissions.py');

  test('Dart and Kotlin agree on the channel and its three methods', () {
    const channel = 'com.crescendoalarm.crescendoalarm/alarm_screen_access';
    expect(dart, contains("'$channel'"));
    expect(access, contains('"$channel"'));
    expect(mainActivity, contains('AlarmScreenAccess.CHANNEL'));
    for (final method in [
      'status',
      'openFullScreenIntentSettings',
      'openOverlaySettings'
    ]) {
      expect(dart, contains("'$method'"), reason: 'Dart calls $method');
      expect(mainActivity, contains('"$method"'),
          reason: 'MainActivity handles $method');
    }
  });

  test('the launcher is installed from the Application, which the manifest '
      'names', () {
    expect(manifest, contains('android:name=".CrescendoApplication"'));
    expect(_read('$_kotlinDir/CrescendoApplication.kt'),
        contains('RingScreenLauncher.install('));
  });

  test('the launcher decides through the policy and acts on the plugin\'s '
      'ringing signal', () {
    expect(launcher, contains('RingScreenLaunchPolicy.decide('));
    expect(launcher, contains('AlarmRingingLiveData.instance'));
    expect(launcher, contains('Intent.FLAG_ACTIVITY_NEW_TASK'));
  });

  test('the overlay permission is declared and on the reviewed allow-list',
      () {
    expect(manifest,
        contains('android.permission.SYSTEM_ALERT_WINDOW'));
    expect(script, contains('"android.permission.SYSTEM_ALERT_WINDOW"'));
  });

  test('the app never draws an overlay window itself', () {
    // The permission is only used to start an activity from the background.
    final dartSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in dartSources) {
      expect(f.readAsStringSync(), isNot(contains('TYPE_APPLICATION_OVERLAY')),
          reason: f.path);
    }
    for (final k in Directory(_kotlinDir).listSync().whereType<File>()) {
      for (final api in [
        'TYPE_APPLICATION_OVERLAY',
        'TYPE_SYSTEM_ALERT',
        'WindowManager',
        '.addView(',
      ]) {
        expect(k.readAsStringSync(), isNot(contains(api)),
            reason: '\${k.path} must not draw: \$api');
      }
    }
  });
}
