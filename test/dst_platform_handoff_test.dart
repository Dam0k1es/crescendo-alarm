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

// docs/TODO.md T-202, docs/timezone-requirements.md TZ-1/TZ-8: an
// APPOINTMENT alarm (a planned instant) must keep its exact instant through
// every hand-off on its way to the platform - including an instant in the
// SECOND pass of a repeated fall-back hour, whose local reading (02:30)
// also names a different, earlier instant (the first pass).
//
// Every hand-off below used to go through that local reading and come back
// as the first pass, one hour early:
//
// - alarmPlatformTime rebuilt a local DateTime from year/month/.../minute;
// - the alarm plugin persists AlarmSettings.dateTime with toIso8601String()
//   and re-arms from that string at every Alarm.init (`_checkAlarm`), so a
//   local-tagged value comes back as the first pass after any restart;
// - ScheduledAlarm.toJson did the same for the app's own alarm list;
// - isAlarmStale compared rebuilt local fields;
// - the Do Not Disturb window is derived from alarmPlatformTime.
//
// Fixtures: second-pass instants built as tz.TZDateTime in Europe/Berlin
// and Australia/Lord_Howe (30-minute DST), plus the process zone's own
// transitions (test/support). The assertions compare instants, so they are
// meaningful under every CI zone; they can only FAIL on the old code where
// the process zone itself has the repeated hour (Berlin, St. John's, Lord
// Howe, Chatham), and are trivially true under UTC and Tokyo.

import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/stored_values.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart';
import 'package:crescendo_alarm/utils/utils.dart';

import 'support/local_zone_transitions.dart';

const _minute = 60 * 1000;
const _hour = 60 * _minute;

/// A second-pass instant, with a description for failure messages.
typedef _Fixture = ({String name, int ms});

AlarmSettings _settingsAt(DateTime at) => buildRingingAlarmSettings(
      id: 7,
      dateTime: at,
      tone: 'assets/sounds/wake_up.mp3',
      gentlewake: false,
      volume: 0.8,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 'Wake up',
      body: 'Your alarm is ringing',
      vibrate: true,
    );

/// What `AlarmStorage.saveAlarm`/`getSavedAlarms` do with it (alarm 5.12.0,
/// lib/service/alarm_storage.dart) - the value `Alarm.init` re-arms from.
AlarmSettings _throughPluginStorage(AlarmSettings settings) =>
    AlarmSettings.fromJson(
        json.decode(json.encode(settings.toJson())) as Map<String, dynamic>);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final transitions = localTransitions();
  final overlaps = transitions.where((t) => t.isOverlap).toList();

  List<_Fixture> secondPasses() {
    final berlin = tz.getLocation('Europe/Berlin');
    final lordHowe = tz.getLocation('Australia/Lord_Howe');
    // 25 Oct 2026, 02:30 CET - the SECOND 02:30 in Berlin (01:30 UTC).
    final berlinSecond = tz.TZDateTime.from(DateTime.utc(2026, 10, 25, 1, 30), berlin);
    // 5 Apr 2026, 01:45 +10:30 - the second 01:45 on Lord Howe (15:15 UTC
    // the day before); its DST is only 30 minutes long.
    final lordHoweSecond =
        tz.TZDateTime.from(DateTime.utc(2026, 4, 4, 15, 15), lordHowe);
    // Guard the fixtures themselves: they really are second passes.
    expect((berlinSecond.hour, berlinSecond.minute), (2, 30));
    expect(berlinSecond.timeZoneOffset, const Duration(hours: 1));
    expect((lordHoweSecond.hour, lordHoweSecond.minute), (1, 45));
    expect(lordHoweSecond.timeZoneOffset, const Duration(hours: 10, minutes: 30));
    return [
      (name: 'Europe/Berlin 2026-10-25 02:30 CET', ms: berlinSecond.millisecondsSinceEpoch),
      (name: 'Australia/Lord_Howe 2026-04-05 01:45 +10:30', ms: lordHoweSecond.millisecondsSinceEpoch),
      for (final t in overlaps)
        (name: 'process zone, $t, second pass', ms: t.secondPassMs(t.wallMiddleMs)),
    ];
  }

  group('(a) alarmPlatformTime preserves the instant', () {
    test('an instant in the second pass stays in the second pass', () {
      for (final f in secondPasses()) {
        final planned = DateTime.fromMillisecondsSinceEpoch(f.ms, isUtc: true);
        final platform = alarmPlatformTime(planned);
        expect(platform.millisecondsSinceEpoch, f.ms,
            reason: '${f.name}: got $platform (${platform.timeZoneOffset})');
        expect(platform.isUtc, isFalse,
            reason: 'still the local reading the boundary promises');
      }
    });

    test('counter-test: the first pass stays in the first pass', () {
      for (final t in overlaps) {
        final first = t.firstPassMs(t.wallMiddleMs);
        expect(alarmPlatformTime(DateTime.fromMillisecondsSinceEpoch(first))
                .millisecondsSinceEpoch,
            first,
            reason: '$t');
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);

    test('counter-test: seconds are still truncated to the minute - also in '
        'the second pass', () {
      for (final f in secondPasses()) {
        final withSeconds = DateTime.fromMillisecondsSinceEpoch(
            f.ms + 42 * 1000 + 500,
            isUtc: true);
        expect(alarmPlatformTime(withSeconds).millisecondsSinceEpoch, f.ms,
            reason: f.name);
      }
      // And on an ordinary day, in the same shape as before.
      final ordinary = DateTime(2026, 7, 10, 6, 30, 45, 123);
      expect(alarmPlatformTime(ordinary), DateTime(2026, 7, 10, 6, 30));
    });
  });

  group('the alarm plugin keeps the instant across its own storage', () {
    test('AlarmSettings built for a second-pass instant survive the plugin\'s '
        'JSON round trip (what Alarm.init re-arms from)', () {
      for (final f in secondPasses()) {
        final at = alarmPlatformTime(DateTime.fromMillisecondsSinceEpoch(f.ms));
        final settings = _settingsAt(at);
        expect(settings.dateTime.millisecondsSinceEpoch, f.ms, reason: f.name);
        final restored = _throughPluginStorage(settings);
        expect(restored.dateTime.millisecondsSinceEpoch, f.ms,
            reason: '${f.name}: the plugin would re-arm at ${restored.dateTime} '
                'after a restart');
      }
    });

    test('counter-test: an ordinary instant round-trips unchanged', () {
      final at = DateTime(2026, 7, 10, 6, 30);
      final restored = _throughPluginStorage(_settingsAt(at));
      expect(restored.dateTime.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
    });
  });

  group('(b) ScheduledAlarm persists its instant unambiguously', () {
    test('a second-pass alarm comes back as the second pass after a restart',
        () {
      for (final f in secondPasses()) {
        // The frame planAlarmSync creates them in (localFromStored).
        final alarm = ScheduledAlarm(time: localFromStored(f.ms)!, id: 1);
        final loaded = ScheduledAlarm.fromJson(alarm.toJson());
        expect((loaded.time as DateTime).millisecondsSinceEpoch, f.ms,
            reason: '${f.name}: loaded ${loaded.time}');
      }
    });

    test('the loaded value is still the local reading (title, alarm list, '
        'pruneScheduledAlarms read its digits) and equals the original', () {
      for (final f in secondPasses()) {
        final alarm = ScheduledAlarm(time: localFromStored(f.ms)!, id: 1);
        final loaded = ScheduledAlarm.fromJson(alarm.toJson());
        expect((loaded.time as DateTime).isUtc, isFalse);
        expect(loaded.title, alarm.title);
        expect(loaded, alarm);
      }
    });

    test('legacy entries (local reading, no offset) are still read as before',
        () {
      final legacy = jsonEncode({
        'time': '2026-07-10T06:30:00.000',
        'enabled': true,
        'gentlewake': false,
        'tone': null,
        'id': 3,
      });
      final loaded = ScheduledAlarm.fromJson(legacy);
      expect(loaded.time, DateTime(2026, 7, 10, 6, 30));
    });
  });

  group('(d) the Do Not Disturb window ends at the true instant', () {
    test('a planned value in the second pass: end and start are the true '
        'instants', () {
      for (final f in secondPasses()) {
        final local = localFromStored(f.ms)!;
        final window = sleepTimeWindow(
          pendingDayValues: {isoDate(local): f.ms},
          disabledDays: const {},
          manualAlarms: const [],
          sleepGoal: const TimeOfDay(hour: 8, minute: 0),
          now: DateTime.fromMillisecondsSinceEpoch(f.ms - 10 * _hour),
        );
        expect(window, isNotNull, reason: f.name);
        expect(window!.end.millisecondsSinceEpoch, f.ms,
            reason: '${f.name}: end ${window.end}');
        expect(window.start.millisecondsSinceEpoch, f.ms - 8 * _hour,
            reason: '${f.name}: an 8 h Sleep Goal is 8 real hours, got '
                '${window.start} -> ${window.end}');
      }
    });

    test('a manual alarm in the repeated hour: the window ends at its second '
        'occurrence', () {
      for (final t in overlaps) {
        final wall = t.wallMiddleMs;
        final f = wallFields(wall);
        final window = sleepTimeWindow(
          pendingDayValues: const {},
          disabledDays: const {},
          manualAlarms: [
            ManualAlarm(time: TimeOfDay(hour: f.hour, minute: f.minute)),
          ],
          sleepGoal: const TimeOfDay(hour: 8, minute: 0),
          now: DateTime.fromMillisecondsSinceEpoch(t.firstPassMs(wall) - 10 * _hour),
        );
        expect(window?.end.millisecondsSinceEpoch, t.secondPassMs(wall),
            reason: '$t: $window');
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);
  });

  group('isAlarmStale compares instants', () {
    test('an alarm as the plugin reports it (UTC-tagged after its storage '
        'round trip) is not stale while it rings', () {
      final ringAt = DateTime.utc(2026, 7, 10, 5, 30);
      final now = DateTime.fromMillisecondsSinceEpoch(
          ringAt.millisecondsSinceEpoch + 30 * 1000);
      expect(isAlarmStale(ringAt, now), isFalse,
          reason: 'the same instant in two frames is the same alarm');
      expect(
          isAlarmStale(
              ringAt,
              DateTime.fromMillisecondsSinceEpoch(
                  ringAt.millisecondsSinceEpoch + _minute)),
          isTrue);
    });

    test('across the repeated hour: the first pass\'s last minute is stale '
        'at the second pass\'s first minute', () {
      for (final t in overlaps) {
        final event =
            DateTime.fromMillisecondsSinceEpoch(t.firstPassMs(t.wallEndMs - _minute));
        final now = DateTime.fromMillisecondsSinceEpoch(t.secondPassMs(t.wallStartMs));
        expect(now.difference(event), const Duration(minutes: 1), reason: '$t');
        expect(isAlarmStale(event, now), isTrue, reason: '$t');
        expect(isAlarmStale(now, event), isFalse, reason: '$t');
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);
  });
}
