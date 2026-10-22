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
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/utils/direct_boot_mirror.dart'
    as direct_boot_mirror;
import 'package:crescendo_alarm/utils/ring_timeout.dart' as ring_timeout;

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-237 (maintainer decision 2026-10-23: a ring nobody stops ends
// itself 60 minutes after its due time and a silent notice says so): the
// native side can only act if Dart tells it, at every real arm and cancel,
// which alarm id is armed for which instant (the timeout fires at due + 60
// minutes, the way the direct-boot mirror and the sleep-time DND window are
// pushed). These tests pin the hooks; the decision itself is
// `RingTimeoutPolicy` (JVM tests) and the wiring is read by
// test/ring_timeout_contract_test.dart.

ManualAlarm _manual(int id, int hour, {bool enabled = true}) => ManualAlarm(
      time: TimeOfDay(hour: hour, minute: 0),
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

void main() {
  final friday = DateTime(2026, 10, 2, 18, 0);
  final saturday7 = DateTime(2026, 10, 3, 7, 0);

  final armed = <({int id, int dueAtMillis})>[];
  final cancelled = <int>[];
  var cancelAllCalls = 0;
  late AppState appState;
  late FakeAlarmPlatform platform;

  setUp(() async {
    armed.clear();
    cancelled.clear();
    cancelAllCalls = 0;
    ring_timeout.armRingTimeout = (id, dueAt) async =>
        armed.add((id: id, dueAtMillis: dueAt.toUtc().millisecondsSinceEpoch));
    ring_timeout.cancelRingTimeout = (id) async => cancelled.add(id);
    ring_timeout.cancelAllRingTimeouts = () async => cancelAllCalls++;
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {};
    SharedPreferences.setMockInitialValues({});
    appState = AppState();
    await appState.initialized;
    platform = FakeAlarmPlatform()..attach(appState);
    armed.clear();
  });

  tearDown(() {
    ring_timeout.armRingTimeout = (id, dueAt) async {};
    ring_timeout.cancelRingTimeout = (id) async {};
    ring_timeout.cancelAllRingTimeouts = () async {};
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {};
  });

  test('arming a manual alarm arms its timeout for the instant it is armed '
      'for', () async {
    final alarm = _manual(41, 7);
    appState.manualAlarms.add(alarm);

    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);

    expect(armed, hasLength(1));
    expect(armed.single.id, 41);
    expect(armed.single.dueAtMillis,
        platform.armed[41]!.dateTime.toUtc().millisecondsSinceEpoch);
    expect(armed.single.dueAtMillis,
        saturday7.toUtc().millisecondsSinceEpoch);
  });

  test('re-arming the same alarm arms the timeout again for the new instant',
      () async {
    final alarm = _manual(41, 7);
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);
    await appState.setManualAlarmEnabled(alarm, true,
        now: () => saturday7.add(const Duration(minutes: 1)));

    expect(armed.map((e) => e.id), [41, 41]);
    expect(armed.last.dueAtMillis,
        saturday7.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch);
  });

  test('switching an alarm off cancels its timeout', () async {
    final alarm = _manual(41, 7);
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);

    await appState.setManualAlarmEnabled(alarm, false);

    expect(cancelled, contains(41));
  });

  test('deleting an alarm cancels its timeout', () async {
    final alarm = _manual(41, 7);
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);

    await appState.removeAlarm(alarm);

    expect(cancelled, contains(41));
  });

  test('stopping the platform alarm (the user\'s Stop) cancels its timeout',
      () async {
    await appState.stopPlatformAlarm(55);

    expect(cancelled, [55]);
  });

  test('stopping every platform alarm cancels every timeout', () async {
    await appState.stopAllPlatformAlarms();

    expect(cancelAllCalls, 1);
  });

  test('a postponed (snoozed) ring gets its own timeout from the minute the '
      'platform alarm is armed for', () async {
    final at = DateTime(2026, 10, 3, 7, 5, 37, 250);

    await appState.setSnoozeAlarm(77, at, true);

    expect(armed, hasLength(1));
    expect(armed.single.id, 77);
    expect(armed.single.dueAtMillis,
        platform.armed[77]!.dateTime.toUtc().millisecondsSinceEpoch);
    expect(armed.single.dueAtMillis,
        DateTime(2026, 10, 3, 7, 5).toUtc().millisecondsSinceEpoch,
        reason: 'floored to the minute, like every platform alarm');
  });

  test('a snooze (stop, then arm the same id) ends armed, not cancelled',
      () async {
    final calls = <String>[];
    ring_timeout.cancelRingTimeout = (id) async => calls.add('cancel $id');
    ring_timeout.armRingTimeout = (id, dueAt) async => calls.add('arm $id');

    await appState.stopPlatformAlarm(77);
    await appState.setSnoozeAlarm(77, DateTime(2026, 10, 3, 7, 5), true);

    expect(calls, ['cancel 77', 'arm 77']);
  });

  test('no alarm is armed at the platform when a timeout hook throws',
      () async {
    ring_timeout.cancelRingTimeout =
        (id) async => throw StateError('channel down');

    await appState.stopPlatformAlarm(55);
  });

  test('a cold start asks the native side to give the plugin\'s own alarms a '
      'timeout', () async {
    var syncs = 0;
    ring_timeout.syncRingTimeouts = () async => syncs++;
    SharedPreferences.setMockInitialValues({});
    final restarted = AppState();
    await restarted.initialized;

    expect(syncs, greaterThanOrEqualTo(1));
  });

  test('a ring that ended by its timeout is rung, not missed: no second ring '
      'and no missed notice for it', () async {
    final alarm = _manual(41, 7);
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);
    // The native timeout stopped the ring at 08:00; the plugin dropped it.
    platform.armed.remove(41);
    ring_timeout.takeTimedOutRingIds = () async => [41];

    final exactlyAtTimeout = saturday7.add(const Duration(minutes: 60));
    await appState.reconcileManualAlarmsWithPlatform(
        now: () => exactlyAtTimeout);

    expect(platform.armed[41]?.dateTime, isNot(saturday7),
        reason: 'not rung a second time at exactly 60:00');
    expect(platform.armedAt(saturday7.add(const Duration(days: 1))), isTrue,
        reason: 'the next occurrence is armed');
  });

  test('a calendar-derived alarm arms its timeout like a manual one',
      () async {
    final due = DateTime(2026, 10, 3, 6, 30);
    await appState.addAlarm(
      ScheduledAlarm(
          time: due,
          enabled: true,
          gentlewake: false,
          tone: 'assets/sounds/lollipop.mp3'),
      now: () => friday,
    );

    expect(armed, hasLength(1));
    expect(armed.single.dueAtMillis, due.toUtc().millisecondsSinceEpoch);
  });

  test('a failing native channel never breaks arming an alarm', () async {
    ring_timeout.armRingTimeout =
        (id, dueAt) async => throw StateError('channel down');
    final alarm = _manual(41, 7);
    appState.manualAlarms.add(alarm);

    final ok = await appState.setManualAlarmEnabled(alarm, true,
        now: () => friday);

    expect(ok, isTrue);
    expect(platform.armedAt(saturday7), isTrue,
        reason: 'the alarm itself is armed regardless');
  });
}
