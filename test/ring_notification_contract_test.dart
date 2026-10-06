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

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';
import 'package:crescendo_alarm/utils/ring_notification.dart';

// docs/TODO.md T-229: source-reading contract between the Dart call, the
// native quieting code and the `alarm` plugin's own notification - the
// parts no `flutter test` can execute.

const _kotlinDir =
    'android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm';

String _read(String path) => File(path).readAsStringSync();

Uri _packageRoot(String name) {
  final config = jsonDecode(
          File('.dart_tool/package_config.json').readAsStringSync())
      as Map<String, dynamic>;
  final root = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == name)['rootUri'] as String;
  return Uri.file('${Directory.current.path}/.dart_tool/')
      .resolve(root.endsWith('/') ? root : '$root/');
}

void main() {
  final quiet = _read('$_kotlinDir/RingNotification.kt');
  final mainActivity = _read('$_kotlinDir/MainActivity.kt');

  test('Dart and MainActivity use the same channel and method', () {
    expect(ringNotificationChannelName,
        'com.crescendoalarm.crescendoalarm/ring_notification');
    expect(quiet, contains('const val CHANNEL = "$ringNotificationChannelName"'));
    expect(mainActivity, contains('RingNotification.CHANNEL'));
    expect(mainActivity, contains('"quiet"'));
    // Exact call shape: the real resumed state, not a constant (a `true`
    // here would quiet the heads-up while the app is in the background,
    // removing the user's way to the ring screen).
    expect(mainActivity, contains('private var resumed = false'));
    expect(mainActivity, contains('RingNotification.quiet(applicationContext, alarmId, resumed)'));
    expect(RegExp(r'override fun onResume\(\) \{\s*super\.onResume\(\)\s*resumed = true\s*\}')
        .hasMatch(mainActivity), isTrue);
    expect(RegExp(r'override fun onPause\(\) \{\s*resumed = false\s*super\.onPause\(\)\s*\}')
        .hasMatch(mainActivity), isTrue);
  });

  test('the quiet channel is new, low importance and makes no sound or '
      'vibration of its own', () {
    final id = RegExp(r'const val QUIET_CHANNEL_ID = "(\w+)"')
        .firstMatch(_read('$_kotlinDir/RingNotificationPolicy.kt'))
        ?.group(1);
    expect(id, isNotNull);
    expect(id, isNot('alarm_plugin_channel'),
        reason: 'an existing channel\'s importance cannot be lowered by the '
            'app, and the plugin\'s must stay HIGH for the locked-screen '
            'full-screen intent');
    expect(quiet, contains('NotificationManager.IMPORTANCE_LOW'));
    expect(quiet, contains('setSound(null, null)'));
    expect(quiet, contains('enableVibration(false)'));
    expect(quiet, contains('setOnlyAlertOnce(true)'));
  });

  test('only the plugin\'s own ringing notification is ever re-posted, '
      'through the policy', () {
    expect(quiet, contains('RingNotificationPolicy.decide('));
    expect(quiet, contains('Notification.Builder.recoverBuilder('),
        reason: 'keeps the plugin\'s content, delete (restore) intent and '
            'actions instead of rebuilding them by hand');
    // Exact call shapes: the real keyguard state and the real notification
    // (a weakened lock check would touch the locked-screen FSI path).
    expect(quiet, contains('RingNotificationPolicy.decide(activityResumed, keyguard.isKeyguardLocked, channelId, flags)'));
    expect(quiet, contains('val flags = active?.flags ?: 0'));
    expect(quiet, contains('val channelId = active?.let(::channelOf)'));
    expect(quiet, contains('fun quiet(context: Context, alarmId: Int, activityResumed: Boolean)'));
    expect(quiet, contains('if (decision != RingNotificationPolicy.Decision.QUIET || active == null)'));
    // A re-post no foreground service claimed (Stop raced) is cancelled.
    expect(quiet, contains('RingNotificationPolicy.isOrphan(posted != null, posted?.flags ?: 0)'));
    expect(quiet, contains('manager.cancel(alarmId)'));
  });

  test('the plugin channel id the native side looks for is the one the '
      'plugin actually uses', () {
    final plugin = File.fromUri(_packageRoot('alarm').resolve(
            'android/src/main/kotlin/com/gdelataillade/alarm/services/NotificationService.kt'))
        .readAsStringSync();
    final pluginId = RegExp(r'private const val CHANNEL_ID = "(\w+)"')
        .firstMatch(plugin)
        ?.group(1);
    expect(pluginId, 'alarm_plugin_channel');
    final policy = _read('$_kotlinDir/RingNotificationPolicy.kt');
    expect(policy, contains('const val PLUGIN_CHANNEL_ID = "$pluginId"'));
    // And the plugin still posts the full-screen intent on that channel at
    // IMPORTANCE_HIGH - the locked-screen launch this fix must not weaken.
    expect(plugin, contains('NotificationManager.IMPORTANCE_HIGH'));
    expect(plugin, contains('setFullScreenIntent(pendingIntent, true)'));
  });

  test('the alarm itself still asks for the full-screen intent', () {
    final settings = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime.utc(2026, 10, 7, 6),
      tone: null,
      gentlewake: false,
      volume: 0.5,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 't',
      body: 'b',
      vibrate: true,
    );
    expect(settings.androidFullScreenIntent, isTrue);
    expect(settings.notificationSettings.androidStopAlarmOnDismiss, isFalse);
  });
}
