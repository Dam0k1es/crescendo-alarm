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
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';

// docs/TODO.md T-237 (maintainer decision 2026-10-23): a ring nobody stops
// ends itself 60 minutes after its due time, with a silent notice. The
// timeout runs natively - it must work with no Flutter engine, after the app
// was swiped away - so Dart and Kotlin have to agree on a few names and one
// number. Same shape as test/direct_boot_fallback_contract_test.dart: source
// reading, because neither side can run the other in `flutter test`.

const _kotlinDir =
    'android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final policy = _read('$_kotlinDir/RingTimeoutPolicy.kt');
  final receiver = _read('$_kotlinDir/RingTimeoutReceiver.kt');
  final timeout = _read('$_kotlinDir/RingTimeout.kt');
  final missed = _read('$_kotlinDir/DirectBootMissedNotification.kt');
  final boot = _read('$_kotlinDir/DirectBootReceiver.kt');
  final mainActivity = _read('$_kotlinDir/MainActivity.kt');
  final dart = _read('lib/utils/ring_timeout.dart');
  final manifest = _read('android/app/src/main/AndroidManifest.xml');

  test('the native timeout is the 60-minute window the plugin already uses '
      'for stale alarms', () {
    expect(overdueRingWindow, const Duration(minutes: 60));
    expect(policy,
        contains('const val TIMEOUT_MINUTES = ${overdueRingWindow.inMinutes}L'));
  });

  test('Dart and Kotlin agree on the channel and its methods', () {
    const channel = 'com.crescendoalarm.crescendoalarm/ring_timeout';
    expect(dart, contains(RegExp("MethodChannel\\(\\s*'$channel'\\s*\\)")));
    expect(timeout, contains('"$channel"'));
    expect(mainActivity, contains('RingTimeout.CHANNEL'));
    for (final method in ['arm', 'cancel', 'cancelAll', 'sync', 'takeTimedOut']) {
      expect(dart, contains("'$method'"), reason: 'Dart calls $method');
      expect(mainActivity, contains('"$method"'),
          reason: 'MainActivity handles $method');
    }
  });

  test('the receiver decides through the policy and reaches the plugin only '
      'through its public stop entry', () {
    expect(receiver, contains('RingTimeoutPolicy.decide('));
    expect(receiver,
        anyOf(contains('handleStopAlarmCommand('), contains('ACTION_ALARM_STOP')),
        reason: 'the plugin\'s own stop path: audio, vibration, foreground '
            'notification and storage are all released by it');
    expect(receiver, isNot(contains('stopAll')),
        reason: 'only the ring that timed out may end (T-216\'s lesson)');
  });

  test('the notice goes through the shared notification object and has its '
      'own wording, not the "phone was restarted" one', () {
    expect(receiver, contains('DirectBootMissedNotification.postUnstopped('));
    expect(missed, contains('fun postUnstopped('));
    expect(missed, contains('rang for 60 minutes'),
        reason: 'the cause is a ring nobody stopped, not a restart');
  });

  test('the timeout is armed with the same exact-alarm call the plugin '
      'uses, and survives a reboot through the device-protected mirror', () {
    expect(timeout, contains('setExactAndAllowWhileIdle'));
    expect(timeout, contains('createDeviceProtectedStorageContext'));
    expect(boot, contains('RingTimeout.rearmAfterBoot('),
        reason: 'AlarmManager entries do not survive a reboot');
  });

  test('the receiver is declared and not exported', () {
    final decl = RegExp(
            r'<receiver[^>]*android:name="\.RingTimeoutReceiver"[^>]*>',
            dotAll: true)
        .firstMatch(manifest)
        ?.group(0);
    expect(decl, isNotNull, reason: 'RingTimeoutReceiver is in the manifest');
    expect(decl, contains('android:exported="false"'));
  });

  test('the plugin internals this relies on are pinned to alarm 5.12.0', () {
    final lock = _read('pubspec.lock');
    final version = RegExp(r'\n  alarm:\n(?:    .*\n)*?    version: "([^"]+)"')
        .firstMatch(lock)
        ?.group(1);
    expect(version, '5.12.0',
        reason: 'RingTimeoutReceiver stops a ring through AlarmService / '
            'ACTION_ALARM_STOP, which are plugin API; re-read them before '
            'a plugin update');
  });
}
