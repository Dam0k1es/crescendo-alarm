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

// docs/TODO.md T-202, docs/timezone-requirements.md TZ-1/TZ-3: a MANUAL
// alarm is a wall-clock alarm ("07:00"), so on a daylight-saving change day
// its reading has to be turned into an instant by the app's own rule:
//
// - a reading in the REPEATED hour rings once, at the LATER occurrence;
// - a reading in the SKIPPED hour rings at the first valid instant after the
//   gap (the transition itself, 03:00 in Europe/Berlin) - never skipped.
//
// Dart's `DateTime(y, m, d, h, min)` does neither (first occurrence; a gap
// reading shifted by the gap length, 02:30 -> 03:30), and that is what
// `nextManualOccurrence` used to build.
//
// The transitions are the PROCESS zone's own (test/support), so each CI leg
// checks its own zone's rules: St. John's (-3:30/-2:30), Lord Howe's
// 30-minute DST, Chatham's 45-minute offsets, Berlin. Under UTC and Tokyo
// there is nothing to resolve and the transition cases are skipped; the
// ordinary-day counter-tests run everywhere.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm_enable.dart';
import 'package:crescendo_alarm/models/scheduling/next_wake_up.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/local_zone_transitions.dart';

const _allDays = {
  DayOfWeek.monday: true,
  DayOfWeek.tuesday: true,
  DayOfWeek.wednesday: true,
  DayOfWeek.thursday: true,
  DayOfWeek.friday: true,
  DayOfWeek.saturday: true,
  DayOfWeek.sunday: true,
};

const _minute = 60 * 1000;
const _hour = 60 * _minute;

TimeOfDay _timeOf(int wallMs) {
  final f = wallFields(wallMs);
  return TimeOfDay(hour: f.hour, minute: f.minute);
}

DateTime _local(int epochMs) => DateTime.fromMillisecondsSinceEpoch(epochMs);

void main() {
  final transitions = localTransitions();
  final overlaps = transitions.where((t) => t.isOverlap).toList();
  final gaps = transitions.where((t) => t.isGap).toList();

  group('repeated hour -> the LATER occurrence (TZ-1)', () {
    test('a reading in the middle of the repeated hour', () {
      for (final t in overlaps) {
        final wall = t.wallMiddleMs;
        // Three hours before the first pass: the alarm is being armed the
        // evening before (or earlier the same night).
        final now = _local(t.firstPassMs(wall) - 3 * _hour);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        expect(result.millisecondsSinceEpoch, t.secondPassMs(wall),
            reason: '$t: ${_timeOf(wall)} must ring at its second '
                'occurrence, got $result (${result.timeZoneOffset})');
        expect(result.isUtc, isFalse);
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);

    test('the first and the last minute of the repeated range', () {
      for (final t in overlaps) {
        for (final wall in [t.wallStartMs, t.wallEndMs - _minute]) {
          final now = _local(t.firstPassMs(wall) - 3 * _hour);
          final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
          expect(result.millisecondsSinceEpoch, t.secondPassMs(wall),
              reason: '$t, reading ${_timeOf(wall)}: got $result');
        }
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);

    test('armed between the two passes, it still rings at the second one', () {
      for (final t in overlaps) {
        final wall = t.wallMiddleMs;
        final now = _local(t.firstPassMs(wall) + _minute);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        expect(result.millisecondsSinceEpoch, t.secondPassMs(wall),
            reason: '$t: got $result');
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);

    test('re-armed right after the second pass rang: no second ring that '
        'night, the next day instead', () {
      for (final t in overlaps) {
        final wall = t.wallMiddleMs;
        final now = _local(t.secondPassMs(wall) + 30 * 1000);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        expect(result.millisecondsSinceEpoch,
            greaterThan(t.secondPassMs(wall) + 20 * _hour),
            reason: '$t: got $result');
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);
  });

  group('skipped hour -> the first valid instant after the gap (TZ-1)', () {
    test('a reading in the middle of the gap rings at the transition', () {
      for (final t in gaps) {
        final wall = t.wallMiddleMs;
        final now = _local(t.instantMs - 3 * _hour);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        // docs/TODO.md T-206 (TZ-2a, maintainer: "Manual alarms: yes"): the
        // transition itself - or the minute before the gap where the
        // transition carries a later date (America/Nuuk).
        expect(result.millisecondsSinceEpoch,
            expectedPlannedInstantMs(transitions, wall),
            reason: '$t: ${_timeOf(wall)} does not exist that day and must '
                'ring as soon as the time exists, got $result');
        expect(result.isUtc, isFalse);
      }
    }, skip: gaps.isEmpty ? noTransitionReason : false);

    test('the first and the last minute of the gap', () {
      for (final t in gaps) {
        for (final wall in [t.wallStartMs, t.wallEndMs - _minute]) {
          final now = _local(t.instantMs - 3 * _hour);
          final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
          expect(result.millisecondsSinceEpoch,
              expectedPlannedInstantMs(transitions, wall),
              reason: '$t, reading ${_timeOf(wall)}: got $result');
        }
      }
    }, skip: gaps.isEmpty ? noTransitionReason : false);

    test('never skipped: it rings that night, not at the next day\'s '
        'reading', () {
      // docs/TODO.md T-206 (TZ-2a): where the gap ends at midnight
      // (America/Nuuk, 28 Mar 2026: 23:00 -> 00:00) the first valid instant
      // after a skipped 23:30 carries the next date; a manual alarm then
      // rings at the minute before the gap (22:59 on the 28th), like a
      // scheduled one - still that night, a day before the next 23:30.
      for (final t in gaps) {
        final wall = t.wallMiddleMs;
        final now = _local(t.instantMs - 3 * _hour);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        final nextDaysReading = wall + 24 * _hour - t.offsetAfterMs;
        expect(result.millisecondsSinceEpoch, lessThan(nextDaysReading),
            reason: '$t: got $result');
        expect(result.millisecondsSinceEpoch,
            expectedPlannedInstantMs(transitions, wall));
      }
    }, skip: gaps.isEmpty ? noTransitionReason : false);

    test('repeatOnDays restricted to the change day still resolves it', () {
      for (final t in gaps) {
        final wall = t.wallMiddleMs;
        final now = _local(t.instantMs - 3 * _hour);
        final changeDay =
            DayOfWeek.values[DateTime.utc(wallFields(wall).year,
                        wallFields(wall).month, wallFields(wall).day)
                    .weekday -
                1];
        final result = nextManualOccurrence(_timeOf(wall), now,
            {for (final d in DayOfWeek.values) d: d == changeDay});
        expect(result.millisecondsSinceEpoch,
            expectedPlannedInstantMs(transitions, wall),
            reason: '$t: got $result');
      }
    }, skip: gaps.isEmpty ? noTransitionReason : false);
  });

  group('counter-tests: readings outside the change hour are unchanged', () {
    test('the minute right before the affected range, on the change day', () {
      for (final t in transitions) {
        final wall = t.wallStartMs - _minute;
        final f = wallFields(wall);
        final now = _local(t.instantMs - 3 * _hour);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        expect(result, DateTime(f.year, f.month, f.day, f.hour, f.minute),
            reason: '$t: ${_timeOf(wall)} is unambiguous');
        expect(result.millisecondsSinceEpoch, wall - t.offsetBeforeMs);
      }
    }, skip: transitions.isEmpty ? noTransitionReason : false);

    test('the first reading after the affected range, on the change day', () {
      for (final t in transitions) {
        final wall = t.wallEndMs;
        final now = _local(t.instantMs - 3 * _hour);
        final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
        expect(result.millisecondsSinceEpoch, wall - t.offsetAfterMs,
            reason: '$t: ${_timeOf(wall)} is unambiguous, got $result');
      }
    }, skip: transitions.isEmpty ? noTransitionReason : false);

    test('an ordinary day in every zone: exactly the local reading', () {
      // 10 Mar 2026 and 15 Jul 2026: no zone in the CI matrix changes its
      // offset on either day.
      for (final now in [DateTime(2026, 3, 10, 5, 0), DateTime(2026, 7, 15, 5, 0)]) {
        for (final time in const [
          TimeOfDay(hour: 0, minute: 0),
          TimeOfDay(hour: 2, minute: 30),
          TimeOfDay(hour: 7, minute: 0),
          TimeOfDay(hour: 23, minute: 59),
        ]) {
          final result = nextManualOccurrence(time, now, _allDays);
          final expectedDay = DateTime(now.year, now.month, now.day, time.hour,
                      time.minute)
                  .isAfter(now)
              ? now.day
              : now.day + 1;
          expect(result,
              DateTime(now.year, now.month, expectedDay, time.hour, time.minute));
        }
      }
    });
  });

  group('every consumer of nextManualOccurrence gets the resolved instant', () {
    test('nextWakeUpTime (bedtime reminder, Do Not Disturb window)', () {
      for (final t in overlaps) {
        final wall = t.wallMiddleMs;
        final now = _local(t.firstPassMs(wall) - 3 * _hour);
        final result = nextWakeUpTime(
          pendingDayValues: const {},
          disabledDays: const {},
          manualAlarms: [ManualAlarm(time: _timeOf(wall), repeatOnDays: _allDays)],
          now: now,
        );
        expect(result?.millisecondsSinceEpoch, t.secondPassMs(wall),
            reason: '$t: got $result');
      }
    }, skip: overlaps.isEmpty ? noTransitionReason : false);

    test('applyManualAlarmEnabled (FR-21 toggle, Handler re-arm) arms it', () async {
      for (final t in [...overlaps, ...gaps]) {
        final wall = t.wallMiddleMs;
        final now = _local(t.instantMs - 3 * _hour);
        final alarm = ManualAlarm(
            time: _timeOf(wall), repeatOnDays: _allDays, enabled: false);
        DateTime? armedAt;
        final ok = await applyManualAlarmEnabled(
          alarm: alarm,
          enabled: true,
          now: now,
          armAlarm: (_, at) async => armedAt = at,
          stopAlarm: (_) async {},
        );
        expect(ok, isTrue);
        expect(armedAt?.millisecondsSinceEpoch,
            expectedPlannedInstantMs(transitions, wall),
            reason: '$t: armed at $armedAt');
        // The alarm's own reading is never rewritten by the resolution.
        expect(alarm.time, _timeOf(wall));
      }
    }, skip: transitions.isEmpty ? noTransitionReason : false);
  });

  // docs/TODO.md T-206, requirements T55 / T206-R21 (maintainer, 2026-09-28:
  // "Manual alarms: yes"): a manual alarm whose reading falls into a gap
  // that ends at midnight rings at the minute before the gap on its own
  // date - R_plan, exactly like a scheduled value - while
  // `localWallClockInstant` itself stays plain TZ-1 R for every other
  // caller. Found generically, so it runs in the America/Nuuk leg and skips
  // everywhere else.
  final laterDateGaps =
      gaps.where((t) => resolvesOntoLaterDate(t, t.wallMiddleMs)).toList();
  test('T55: a manual 23:30 in the midnight-ending gap rings at 22:59 on the '
      'same date; localWallClockInstant stays plain R', () {
    for (final t in laterDateGaps) {
      final wall = t.wallMiddleMs;
      final f = wallFields(wall);
      final now = _local(t.instantMs - 3 * _hour);
      final result = nextManualOccurrence(_timeOf(wall), now, _allDays);
      expect(result.millisecondsSinceEpoch, t.instantMs - _minute,
          reason: '$t: got $result');
      expect(result.day, f.day, reason: '$t: rings on its own date');
      expect(
          localWallClockInstant(f.year, f.month, f.day, f.hour, f.minute)
              .millisecondsSinceEpoch,
          t.instantMs,
          reason: '$t: plain R (T-202) is unchanged');
    }
  },
      skip: laterDateGaps.isEmpty
          ? 'no gap in the process zone resolves onto a later date (only '
              'America/Nuuk, Godthab, Scoresbysund have one, 2026/27)'
          : false);
}
