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

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/utils/direct_boot_mirror.dart'
    as direct_boot_mirror;
import 'package:crescendo_alarm/utils/notifications.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-234 (maintainer decision 2026-10-20: "sinnvoll und
// pragmatisch"): an occurrence of a manual alarm that passed while the app
// was force-stopped is no longer lost silently - on opening, it rings late if
// it is at most `overdueRingWindow` (60 min, T-217) overdue, and is otherwise
// reported with the same "Alarm missed" notice the native direct-boot path
// posts (same notification id, so Android 15+ shows one, not two).
// Reproduced on a real phone (Android 13, 2026-10-20, device-trial H3/H4):
// nothing rang, nothing was reported, the alarm was quietly re-armed.

const _missedNoticeId = 0x217;

class _RecordingNotifications implements Notifications {
  final List<({int? id, String? title, String? body})> posted = [];

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    posted.add((id: id, title: title, body: body));
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}

  List<({int? id, String? title, String? body})> get missedNotices =>
      posted.where((n) => n.id == _missedNoticeId).toList();
}

ManualAlarm _manual(int id, int hour, {bool enabled = true}) => ManualAlarm(
      time: TimeOfDay(hour: hour, minute: 0),
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

Future<void> _open(
        AppState appState, DateTime now, _RecordingNotifications n) =>
    runCheckpointSafely(
      appState,
      trigger: CheckpointTrigger.appForeground,
      now: () => now,
      fetchEvents: (from, to) async => [],
      notifications: n,
    );

void main() {
  // Armed Friday evening for Saturday 07:00 (the alarm's next occurrence).
  final friday = DateTime(2026, 10, 2, 18, 0);
  final due = DateTime(2026, 10, 3, 7, 0);

  tearDown(() {
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {};
  });

  Future<(AppState, FakeAlarmPlatform, ManualAlarm)> armedAndStopped() async {
    final appState = await _freshAppState();
    final platform = FakeAlarmPlatform()..attach(appState);
    final alarm = _manual(21, 7);
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);
    expect(platform.armedAt(due), isTrue, reason: 'precondition');
    platform.setIds.clear();
    return (appState, platform, alarm);
  }

  test('overdue by 30 minutes: rings late on opening, no notice', () async {
    final (appState, platform, _) = await armedAndStopped();
    final n = _RecordingNotifications();
    final opened = due.add(const Duration(minutes: 30));

    platform.forceStopAndRelaunch(opened);
    await _open(appState, opened, n);

    expect(platform.setIds, [21]);
    final settings = platform.armed[21]!;
    expect(settings.dateTime.isAfter(opened), isFalse,
        reason: 'armed for a time that is not in the future: the plugin '
            'rings it at once');
    expect(settings.dateTime.isBefore(due), isFalse);
    expect(n.missedNotices, isEmpty);
  });

  test('exactly the overdue window late still rings, one minute more is '
      'reported instead', () async {
    final (appState, platform, _) = await armedAndStopped();
    final n = _RecordingNotifications();
    final edge = due.add(overdueRingWindow);

    platform.forceStopAndRelaunch(edge);
    await _open(appState, edge, n);
    expect(n.missedNotices, isEmpty, reason: 'inside the window');
    expect(platform.armed[21]!.dateTime.isAfter(edge), isFalse);

    final (appState2, platform2, _) = await armedAndStopped();
    final n2 = _RecordingNotifications();
    final late = edge.add(const Duration(minutes: 1));
    platform2.forceStopAndRelaunch(late);
    await _open(appState2, late, n2);
    expect(n2.missedNotices, hasLength(1));
  });

  test('overdue by two hours: one "Alarm missed" notice naming the time, '
      're-armed for the next occurrence, nothing rings now', () async {
    final (appState, platform, _) = await armedAndStopped();
    final n = _RecordingNotifications();
    final opened = due.add(const Duration(hours: 2));

    platform.forceStopAndRelaunch(opened);
    await _open(appState, opened, n);

    expect(n.missedNotices, hasLength(1));
    final notice = n.missedNotices.single;
    expect(notice.title, 'Alarm missed');
    expect(notice.body, contains('07:00'));
    expect(platform.armedAt(DateTime(2026, 10, 4, 7, 0)), isTrue,
        reason: 'the next occurrence is armed');
    expect(platform.armed[21]!.dateTime.isAfter(opened), isTrue,
        reason: 'and nothing is due now');
  });

  test('the notice is posted once, not on every later opening', () async {
    final (appState, platform, _) = await armedAndStopped();
    final n = _RecordingNotifications();
    final opened = due.add(const Duration(hours: 2));

    platform.forceStopAndRelaunch(opened);
    await _open(appState, opened, n);
    await _open(appState, opened.add(const Duration(hours: 1)), n);
    await _open(appState, opened.add(const Duration(hours: 5)), n);

    expect(n.missedNotices, hasLength(1));
  });

  test('more than 48 hours overdue: re-armed silently', () async {
    final (appState, platform, _) = await armedAndStopped();
    final n = _RecordingNotifications();
    final opened = due.add(const Duration(hours: 49));

    platform.forceStopAndRelaunch(opened);
    await _open(appState, opened, n);

    expect(n.missedNotices, isEmpty);
    expect(platform.armed.keys, [21]);
  });

  test('an alarm that rang is never reported or rung again', () async {
    final (appState, platform, _) = await armedAndStopped();
    final n = _RecordingNotifications();
    // Dart saw the ring (Handler.handleAlarm) ...
    appState.markManualAlarmRang(21);
    // ... and the platform no longer holds it afterwards.
    final opened = due.add(const Duration(minutes: 20));
    platform.armed.clear();
    await _open(appState, opened, n);

    expect(n.missedNotices, isEmpty);
    expect(platform.armed[21]!.dateTime.isAfter(opened), isTrue,
        reason: 're-armed for the next occurrence, not rung again');
  });

  test('a switched-off alarm is neither rung nor reported', () async {
    final (appState, platform, alarm) = await armedAndStopped();
    final n = _RecordingNotifications();
    await appState.setManualAlarmEnabled(alarm, false);
    platform.armed.clear();
    final opened = due.add(const Duration(minutes: 20));

    await _open(appState, opened, n);

    expect(n.missedNotices, isEmpty);
    expect(platform.armed, isEmpty);
  });

  test('a deleted alarm leaves nothing behind', () async {
    final (appState, _, alarm) = await armedAndStopped();
    expect(appState.manualArmedFor, contains(21));

    await appState.removeAlarm(alarm);

    expect(appState.manualArmedFor, isNot(contains(21)));
  });

  test('the armed time survives a restart of the app', () async {
    final (appState, _, _) = await armedAndStopped();
    final armedFor = appState.manualArmedFor[21];
    expect(armedFor, isNotNull);

    final restarted = AppState();
    await restarted.initialized;

    expect(restarted.manualArmedFor[21], armedFor);
  });
}
