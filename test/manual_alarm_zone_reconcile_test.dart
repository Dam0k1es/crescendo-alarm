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
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/utils/direct_boot_mirror.dart'
    as direct_boot_mirror;
import 'package:crescendo_alarm/utils/notifications.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-205 / audit M2-01 (maintainer decision 2026-10-23: "beim
// Oeffnen/Fortsetzen neu aufloesen"): a manual alarm is a wall-clock time. It
// was armed as ONE absolute instant and never looked at again, so a changed
// device time zone - or changed zone rules - left it ringing hours off
// (device-trial, Android 13: armed 12:04 Berlin, zone switched to Tokyo,
// still armed for 19:04 Tokyo local, the list still saying "12:04").
//
// The reconcile step of every checkpoint (it runs on app open and on every
// resume, before FR-17's daily lock) therefore compares each enabled manual
// alarm's armed instant on the platform with its next occurrence under the
// CURRENT rules and re-arms it on a difference.
//
// A zone change cannot be simulated inside one test process (the zone is the
// process's), so the difference is produced the way a zone change produces it:
// the platform entry's instant is moved while the alarm's wall-clock time is
// not. The identity cases (nothing to do when nothing changed) run in all ten
// CI zones.

class _SilentNotifications implements Notifications {
  @override
  Future<int> scheduleNotification(
          {String? title, String? body, DateTime? scheduledDate, int? id}) async =>
      id ?? 1;
  @override
  Future<void> cancelAllNotifications() async {}
  @override
  Future<void> cancelNotification(int id) async {}
  @override
  Future<void> init() async {}
}

ManualAlarm _manual(int id, int hour,
        {int minute = 0, bool enabled = true, Map<DayOfWeek, bool>? repeat}) =>
    ManualAlarm(
      time: TimeOfDay(hour: hour, minute: minute),
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
      repeatOnDays: repeat,
    );

// `now` is the device's local clock in production (`DateTime.now()`); an
// instant taken from the platform (UTC-tagged) is converted, or its digits
// would be read as local ones in a zone that is not UTC.
Future<void> _open(AppState appState, DateTime now) => runCheckpointSafely(
      appState,
      trigger: CheckpointTrigger.appForeground,
      now: () => now.toLocal(),
      fetchEvents: (from, to) async => [],
      notifications: _SilentNotifications(),
    );

void main() {
  final friday = DateTime(2026, 10, 2, 18, 0);
  final saturday7 = DateTime(2026, 10, 3, 7, 0);
  final openedAt = DateTime(2026, 10, 2, 19, 0);

  tearDown(() {
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {};
  });

  Future<(AppState, FakeAlarmPlatform, ManualAlarm)> armed() async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    final platform = FakeAlarmPlatform()..attach(appState);
    final alarm = _manual(31, 7);
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);
    expect(platform.armedAt(saturday7), isTrue, reason: 'precondition');
    platform.setIds.clear();
    return (appState, platform, alarm);
  }

  void moveInstant(FakeAlarmPlatform platform, int id, Duration by) {
    final s = platform.armed[id]!;
    platform.armed[id] = s.copyWith(dateTime: s.dateTime.add(by));
  }

  test('nothing changed: opening the app does not touch an armed manual '
      'alarm (all ten zones)', () async {
    final (appState, platform, _) = await armed();

    await _open(appState, openedAt);
    await _open(appState, openedAt.add(const Duration(minutes: 5)));

    expect(platform.setIds, isEmpty, reason: 'no churn when nothing changed');
    expect(platform.armedAt(saturday7), isTrue);
  });

  test('the armed instant is hours off the alarm\'s wall-clock time (a '
      'zone change): it is re-armed once to the next occurrence', () async {
    final (appState, platform, _) = await armed();
    moveInstant(platform, 31, const Duration(hours: 7)); // Berlin -> Tokyo

    await _open(appState, openedAt);

    expect(platform.setIds, [31]);
    expect(platform.armedAt(saturday7), isTrue);
    expect(appState.manualArmedFor[31],
        saturday7.toUtc().millisecondsSinceEpoch,
        reason: 'the recorded armed instant follows (T-234)');

    await _open(appState, openedAt.add(const Duration(minutes: 5)));
    expect(platform.setIds, [31], reason: 'and then it stays put');
  });

  test('the instant moved the other way (travelling west) is re-armed too',
      () async {
    final (appState, platform, _) = await armed();
    moveInstant(platform, 31, const Duration(hours: -6));

    await _open(appState, openedAt);

    expect(platform.setIds, [31]);
    expect(platform.armedAt(saturday7), isTrue);
  });

  test('a difference below one minute is not a difference', () async {
    final (appState, platform, _) = await armed();
    moveInstant(platform, 31, const Duration(seconds: 30));

    await _open(appState, openedAt);

    expect(platform.setIds, isEmpty);
  });

  test('only the alarms that differ are re-armed', () async {
    final (appState, platform, _) = await armed();
    final other = _manual(32, 9);
    appState.manualAlarms.add(other);
    await appState.setManualAlarmEnabled(other, true, now: () => friday);
    platform.setIds.clear();
    moveInstant(platform, 32, const Duration(hours: 7));

    await _open(appState, openedAt);

    expect(platform.setIds, [32]);
  });

  test('an alarm that is ringing right now is never moved', () async {
    final (appState, platform, _) = await armed();
    moveInstant(platform, 31, const Duration(hours: 7));
    platform.ringing.add(31);

    await _open(appState, openedAt);

    expect(platform.setIds, isEmpty);
  });

  test('an entry whose instant is already past (a late or ringing alarm) is '
      'left to its own handling', () async {
    final (appState, platform, _) = await armed();
    final s = platform.armed[31]!;
    platform.armed[31] = s.copyWith(
        dateTime: openedAt.subtract(const Duration(minutes: 10)));

    await _open(appState, openedAt);

    expect(platform.setIds, isEmpty);
  });

  test('a switched-off alarm is never armed by this path', () async {
    final (appState, platform, alarm) = await armed();
    await appState.setManualAlarmEnabled(alarm, false);
    platform.setIds.clear();
    platform.armed.clear();

    await _open(appState, openedAt);

    expect(platform.setIds, isEmpty);
    expect(platform.armed, isEmpty);
  });

  test('a repeating alarm armed for the wrong weekday is put on its next '
      'selected day', () async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    final platform = FakeAlarmPlatform()..attach(appState);
    final alarm = _manual(33, 7, repeat: {
      for (final d in DayOfWeek.values) d: d == DayOfWeek.saturday
    });
    appState.manualAlarms.add(alarm);
    await appState.setManualAlarmEnabled(alarm, true, now: () => friday);
    platform.setIds.clear();
    moveInstant(platform, 33, const Duration(days: 2));

    await _open(appState, openedAt);

    expect(platform.setIds, [33]);
    expect(platform.armedAt(saturday7), isTrue);
  });

  test('scheduled (calendar-derived) alarms are not touched by this path',
      () async {
    // FR-18 owns them; this reconcile only looks at manual alarms.
    final (appState, platform, _) = await armed();
    expect(appState.scheduledAlarms, isEmpty);
    await _open(appState, openedAt);
    expect(platform.armed.keys, [31]);
  });

  // ---- review additions (independent review, 2026-10-23) ----------------

  group('sub-minute tolerance: the platform entry is floored to the minute, '
      'so only a whole-minute difference counts', () {
    for (final (label, delta, rearm) in [
      ('-30 s', const Duration(seconds: -30), false),
      ('+59.999 s', const Duration(milliseconds: 59999), false),
      ('+60 s', const Duration(seconds: 60), true),
      ('-60 s', const Duration(seconds: -60), true),
    ]) {
      test(label, () async {
        final (appState, platform, _) = await armed();
        moveInstant(platform, 31, delta);

        await _open(appState, openedAt);

        expect(platform.setIds, rearm ? [31] : isEmpty);
      });
    }
  });

  group('shifts that cross a date boundary or look like DST', () {
    for (final (label, delta) in [
      ('+20 h (lands on Sunday)', const Duration(hours: 20)),
      ('-9 h (lands on Friday night)', const Duration(hours: -9)),
      ('+1 h (a rules change, same zone)', const Duration(hours: 1)),
      ('-2 h', const Duration(hours: -2)),
    ]) {
      test(label, () async {
        final (appState, platform, _) = await armed();
        moveInstant(platform, 31, delta);

        await _open(appState, openedAt);

        expect(platform.setIds, [31]);
        expect(platform.armedAt(saturday7), isTrue);
      });
    }

    test('a westward trip: the old instant is EARLIER than the new next '
        'occurrence but still in the future - it is moved', () async {
      final (appState, platform, _) = await armed();
      moveInstant(platform, 31, const Duration(hours: -6));

      await _open(appState, openedAt);

      expect(platform.armedAt(saturday7), isTrue);
    });
  });

  group('entries this path must leave alone', () {
    test('an entry exactly at "now" or already past is skipped (a late '
        'ring armed by T-234 is not "corrected")', () async {
      final (appState, platform, _) = await armed();
      final s = platform.armed[31]!;
      final armedFor = appState.manualArmedFor[31];
      platform.armed[31] = s.copyWith(dateTime: openedAt);

      await _open(appState, openedAt);
      await _open(appState, openedAt.add(const Duration(minutes: 2)));

      expect(platform.setIds, isEmpty);
      expect(appState.manualArmedFor[31], armedFor);
    });

    test('a ringing alarm keeps its recorded armed instant', () async {
      final (appState, platform, _) = await armed();
      final armedFor = appState.manualArmedFor[31];
      moveInstant(platform, 31, const Duration(hours: 7));
      platform.ringing.add(31);

      await _open(appState, openedAt);

      expect(appState.manualArmedFor[31], armedFor);
    });

    test('a platform entry with an id the app does not list (a snoozed '
        'ring) is never adopted or stopped', () async {
      final (appState, platform, _) = await armed();
      final snoozed = platform.armed[31]!.copyWith(
          id: 777, dateTime: saturday7.add(const Duration(days: 3)));
      platform.armed[777] = snoozed;

      await _open(appState, openedAt);

      expect(platform.setIds, isEmpty);
      expect(platform.stopIds, isNot(contains(777)));
      expect(platform.armed.containsKey(777), isTrue);
    });

    test('a switched-off alarm with a stale platform entry is not touched '
        'by this path', () async {
      final (appState, platform, alarm) = await armed();
      alarm.enabled = false;
      moveInstant(platform, 31, const Duration(hours: 7));

      await _open(appState, openedAt);

      expect(platform.setIds, isEmpty);
    });

    test('a repeating alarm legitimately armed for NEXT Saturday (today is '
        'Saturday, after its time) is not pulled to the nearer one',
        () async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState();
      await appState.initialized;
      final platform = FakeAlarmPlatform()..attach(appState);
      final alarm = _manual(34, 7, repeat: {
        for (final d in DayOfWeek.values) d: d == DayOfWeek.saturday
      });
      appState.manualAlarms.add(alarm);
      final satMorning = DateTime(2026, 10, 3, 9, 0); // after 07:00
      await appState.setManualAlarmEnabled(alarm, true, now: () => satMorning);
      platform.setIds.clear();
      expect(platform.armedAt(DateTime(2026, 10, 10, 7, 0)), isTrue,
          reason: 'precondition: armed for next Saturday');

      await _open(appState, satMorning.add(const Duration(hours: 1)));

      expect(platform.setIds, isEmpty);
    });

    test('no repeat day selected (the day-agnostic path) is stable too',
        () async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState();
      await appState.initialized;
      final platform = FakeAlarmPlatform()..attach(appState);
      final alarm = _manual(37, 7, repeat: {
        for (final d in DayOfWeek.values) d: false
      });
      appState.manualAlarms.add(alarm);
      await appState.setManualAlarmEnabled(alarm, true, now: () => friday);
      expect(platform.armedAt(saturday7), isTrue, reason: 'precondition');
      platform.setIds.clear();

      for (final minutes in [0, 30, 300, 600]) {
        await _open(appState, openedAt.add(Duration(minutes: minutes)));
      }

      expect(platform.setIds, isEmpty);

      moveInstant(platform, 37, const Duration(hours: 7));
      await _open(appState, openedAt);
      expect(platform.setIds, [37], reason: 'and it is corrected like any');
    });
  });

  group('two enabled alarms with the same wall-clock time', () {
    test('both are corrected, each once', () async {
      final (appState, platform, _) = await armed();
      final twin = _manual(35, 7);
      appState.manualAlarms.add(twin);
      await appState.setManualAlarmEnabled(twin, true, now: () => friday);
      platform.setIds.clear();
      moveInstant(platform, 31, const Duration(hours: 7));
      moveInstant(platform, 35, const Duration(hours: 7));

      await _open(appState, openedAt);

      expect(platform.setIds.toSet(), {31, 35});
      expect(platform.setIds, hasLength(2));
    });
  });

  group('platform failures never break the reconcile', () {
    test('an unreadable platform state does nothing and does not throw',
        () async {
      final (appState, platform, _) = await armed();
      moveInstant(platform, 31, const Duration(hours: 7));
      appState.debugPlatformGetAll = () async => throw StateError('down');

      await _open(appState, openedAt);

      expect(platform.setIds, isEmpty);
    });

    test('a failing set for one alarm does not stop the others', () async {
      final (appState, platform, _) = await armed();
      final other = _manual(36, 9);
      appState.manualAlarms.add(other);
      await appState.setManualAlarmEnabled(other, true, now: () => friday);
      platform.setIds.clear();
      moveInstant(platform, 31, const Duration(hours: 7));
      moveInstant(platform, 36, const Duration(hours: 7));
      final inner = appState.debugPlatformSet!;
      appState.debugPlatformSet = (settings) async {
        if (settings.id == 31) throw StateError('set failed');
        await inner(settings);
      };

      await _open(appState, openedAt);

      expect(platform.setIds, contains(36));
    });
  });

  group('no churn at DST-shaped moments (identity in every CI zone)', () {
    // The rule must be idempotent wherever the zone has a transition: both
    // the arming and the comparison resolve through the same function, so
    // arming and then opening - at any time before the ring - must never
    // re-arm. The dates are the 2026 transitions of the CI zones (Berlin,
    // Dublin, Troll 10-25 and 03-29, Nuuk 03-28, Lord Howe 10-04,
    // St. John's 03-08 and 11-01, Chatham 04-05, Santiago 09-06); in a zone
    // without a transition on a date the identity holds trivially.
    final days = [
      DateTime(2026, 10, 25),
      DateTime(2026, 3, 29),
      DateTime(2026, 3, 28),
      DateTime(2026, 10, 4),
      DateTime(2026, 3, 8),
      DateTime(2026, 11, 1),
      DateTime(2026, 4, 5),
      DateTime(2026, 9, 6),
    ];
    final times = [(0, 30), (1, 30), (2, 30), (3, 0), (23, 30)];
    for (final day in days) {
      for (final (h, m) in times) {
        test('${day.month}/${day.day} alarm at $h:$m', () async {
          SharedPreferences.setMockInitialValues({});
          final appState = AppState();
          await appState.initialized;
          final platform = FakeAlarmPlatform()..attach(appState);
          final alarm = _manual(40, h, minute: m);
          appState.manualAlarms.add(alarm);
          final armTime = DateTime(day.year, day.month, day.day - 1, 20);
          await appState.setManualAlarmEnabled(alarm, true,
              now: () => armTime);
          final dueAt = platform.armed[40]!.dateTime;
          platform.setIds.clear();

          for (final open in [
            armTime.add(const Duration(minutes: 1)),
            armTime.add(const Duration(hours: 6)),
            dueAt.subtract(const Duration(hours: 1)),
            dueAt.subtract(const Duration(minutes: 1)),
            dueAt.subtract(const Duration(seconds: 30)),
          ]) {
            await _open(appState, open);
            await _open(appState, open);
          }

          expect(platform.setIds, isEmpty,
              reason: 'armed for $dueAt: opening must not move it');
        });
      }
    }
  });
}
