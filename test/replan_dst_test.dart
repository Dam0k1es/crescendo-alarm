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

// Ids used below - tests T01 ..., requirements T206-R1 ..., and "requirements"
// section numbers such as b.0 or 8.2 - are defined in
// docs/t206-dst-requirements.md (not docs/TODO.md items: T33 is not T-33).

// docs/TODO.md T-206 at the replan()/checkpoint level: the derived cases of
// the requirements' test table that need AppState, persistence or the real
// ring sequence.
//
// Two kinds (requirements b.0):
//
// - PROCESS-ZONE twins (TW1, TW3, TW5, TW8b, T11-T13, T32p, T54): nothing is
//   injected - `replan` uses the device rules, i.e. the `TZ` of this test
//   process - so each CI leg exercises its OWN 2026 transitions, found at
//   runtime by test/support/local_zone_transitions.dart (an hourly scan plus
//   bisection, not the production resolver). No zone's digits are
//   hard-coded; each expectation is "reads 07:00 on its own date" or the
//   closed-form R_plan of that helper. They skip under UTC and Asia/Tokyo.
//   Their bodies use only APIs that exist at 8ac1d9e (the file as a whole
//   does not compile there), so they fail there on behaviour, not on
//   signatures; the red-first evidence for this change is the mutation runs
//   recorded in docs/TODO.md T-206, not a staged history.
// - INJECTED cases (T04, T33, T43-T51, T56): Europe/Berlin rules from
//   `package:timezone`, `now` as a `tz.TZDateTime`, exact digits from the
//   requirements' section 8; identical in every leg.

import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/local_zone_transitions.dart';
import 'support/zone_rules.dart';

const _minuteMs = 60 * 1000;
const _hourMs = 60 * _minuteMs;
const _dayMs = 24 * _hourMs;

class _SilentNotifications implements Notifications {
  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async =>
      id ?? 1;

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

Future<AppState> _freshAppState({
  Map<String, Object> prefs = const {},
  TimeOfDay? preferred,
  int maxDeltaMinutes = 30,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  appState.preferredWakeUpTime = preferred;
  appState.maxDailyDelta = Duration(minutes: maxDeltaMinutes);
  return appState;
}

Meeting _meeting(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
    );

/// A unique local reading on [day] as a local instant.
DateTime _at(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

DateTime _local(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

String _reads(int ms) {
  final t = _local(ms);
  return '${isoDate(t)} ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')} local';
}

/// Whether the stored value [ms] reads [hour]:[minute] on [day] in the
/// process zone.
bool _readsOn(int? ms, DateTime day, int hour, int minute) {
  if (ms == null) return false;
  final t = _local(ms);
  return isoDate(t) == isoDate(day) && t.hour == hour && t.minute == minute;
}

Map<String, dynamic> _json(SharedPreferences prefs, String key) {
  final raw = prefs.getString(key);
  expect(raw, isNotNull, reason: 'SharedPreferences key "$key" is missing');
  return jsonDecode(raw!) as Map<String, dynamic>;
}

/// The first date whose 07:00 lies after the transition (requirements 8.2).
DateTime _d07(LocalTransition t) {
  final d = localDateOfWall(t.instantMs + t.offsetAfterMs);
  return wallMsOn(d, 7, 0) - t.offsetAfterMs > t.instantMs
      ? d
      : dayMarker(d, 1);
}

int _ms(int month, int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, month, day, hour, minute).millisecondsSinceEpoch;

void main() {
  late tz.Location berlin;
  late ZoneOffsetAt berlinRules;
  setUpAll(() {
    tzdata.initializeTimeZones();
    berlin = tz.getLocation('Europe/Berlin');
    berlinRules = zoneRules(berlin);
  });
  setUp(Diag.resetForTest);

  final transitions = localTransitions();
  final transitions2026 = transitions
      .where((t) =>
          DateTime.fromMillisecondsSinceEpoch(t.instantMs, isUtc: true).year ==
          2026)
      .toList();
  final gaps2026 = transitions2026.where((t) => t.isGap).toList();
  final noDst = transitions2026.isEmpty ? noTransitionReason : null;

  // -------------------------------------------------------------------------
  // Stage S1
  // -------------------------------------------------------------------------

  group('T04: checkpoint 1 records the rules at its own instant', () {
    for (final (label, now) in [
      ('now as a Berlin TZDateTime', () => tz.TZDateTime(berlin, 2026, 3, 29, 3, 30)),
      // A UTC-tagged `now` carries no offset of its own - so this variant
      // tells "offsetAt(now)" apart from "now.timeZoneOffset".
      ('now as a UTC-tagged instant', () => DateTime.utc(2026, 3, 29, 1, 30)),
    ]) {
      test(label, () async {
        final appState = await _freshAppState();
        await runSchedulingCheckpoint(
          appState,
          trigger: CheckpointTrigger.appForeground,
          now: now,
          offsetAt: berlinRules,
          fetchEvents: (from, to) async => [],
          notifications: _SilentNotifications(),
        );
        expect(appState.lastCheckedUtcOffset, const Duration(hours: 2));
      });
    }
  });

  // -------------------------------------------------------------------------
  // Stage S2 - FR-2 day assignment (T-119)
  // -------------------------------------------------------------------------

  group('T11-T13: an appointment is assigned by the rules at its own instant',
      () {
    /// T11's appointment: the day after the change date, |Δ|/2 after
    /// midnight (gap) or before the next midnight (overlap) - a unique
    /// reading that a one-offset plan made BEFORE the change reads on the
    /// neighbouring date.
    ({DateTime dAfter, DateTime event, DateTime neighbour, int minuteOfDay})
        t11Case(LocalTransition t) {
      final dateL = localDateOfWall(t.instantMs + t.offsetAfterMs);
      final dAfter = dayMarker(dateL, 1);
      final half = (t.offsetAfterMs - t.offsetBeforeMs).abs() ~/ 2 ~/ _minuteMs;
      final minuteOfDay = t.isGap ? half : 24 * 60 - half;
      return (
        dAfter: dAfter,
        event: DateTime(dAfter.year, dAfter.month, dAfter.day, 0, minuteOfDay),
        neighbour: dayMarker(dAfter, t.isGap ? -1 : 1),
        minuteOfDay: minuteOfDay,
      );
    }

    Future<AppState> planAcross(LocalTransition t, DateTime event) async {
      final dateL = localDateOfWall(t.instantMs + t.offsetAfterMs);
      final ringDay = dayMarker(dateL, -1);
      // Held without a preferredWakeUpTime, and LATER than the appointment
      // on its day, so the day is clamped to it (instant-anchored).
      final hold = _at(ringDay, t.isGap ? 12 : 23, t.isGap ? 0 : 59);
      final appState = await _freshAppState();
      appState.lastProcessedConcludedDay = ringDay;
      appState.pendingDayValues = {isoDate(ringDay): hold.millisecondsSinceEpoch};
      await replan(
        appState,
        now: () => hold,
        fetchEvents: (from, to) async => [_meeting(event)],
        todayAlreadyRang: true,
      );
      return appState;
    }

    test('T11: the appointment day is clamped to it, not its neighbour',
        () async {
      for (final t in transitions2026) {
        final c = t11Case(t);
        final appState = await planAcross(t, c.event);
        expect(appState.pendingDayInstantAnchored[isoDate(c.dAfter)], isTrue,
            reason: '$t: the appointment at ${_reads(c.event.millisecondsSinceEpoch)} '
                'belongs to ${isoDate(c.dAfter)}');
        expect(appState.pendingDayValues[isoDate(c.dAfter)],
            c.event.millisecondsSinceEpoch,
            reason: '$t: ${isoDate(c.dAfter)} is exactly the appointment');
        expect(appState.pendingDayInstantAnchored[isoDate(c.neighbour)] ?? false,
            isFalse,
            reason: '$t: the neighbour ${isoDate(c.neighbour)} has no '
                'appointment');
      }
    }, skip: noDst);

    test('T12: FR-12\'s day advance assigns by the same rules', () async {
      // The mirror of T11 (see the report on requirement T12): the day
      // advance runs AFTER the change, so the one offset it used to read
      // with is the new one - and what it misreads is an appointment shortly
      // BEFORE the change, within |Δ| of a midnight. Gap: the last |Δ|/2
      // before a midnight (the new offset pushes it past midnight);
      // overlap: the first |Δ|/2 after one (pulled back before it).
      for (final t in transitions2026) {
        final half = (t.offsetAfterMs - t.offsetBeforeMs).abs() ~/ 2;
        // The latest midnight M with the event still a unique reading
        // before the affected range.
        var m = t.wallStartMs - t.wallStartMs % _dayMs;
        if (t.isOverlap && m + half >= t.wallStartMs) m -= _dayMs;
        final eventWall = t.isGap ? m - half : m + half;
        final event = _local(eventWall - t.offsetBeforeMs);
        final dEvent = localDateOfWall(eventWall);
        final neighbour = dayMarker(dEvent, t.isGap ? 1 : -1);
        final first = dEvent.isBefore(neighbour) ? dEvent : neighbour;
        var ringDay = dEvent.isBefore(neighbour) ? neighbour : dEvent;
        while (!_at(ringDay, 12, 0).isAfter(_local(t.instantMs))) {
          ringDay = dayMarker(ringDay, 1);
        }

        final appState = await _freshAppState();
        final lastProcessed = dayMarker(first, -1);
        appState.lastProcessedConcludedDay = lastProcessed;
        appState.pendingDayValues = {
          for (var d = lastProcessed;
              !d.isAfter(ringDay);
              d = dayMarker(d, 1))
            isoDate(d): _at(d, 12, 0).millisecondsSinceEpoch,
        };
        final result = await replan(
          appState,
          now: () => _at(ringDay, 12, 0),
          fetchEvents: (from, to) async => [_meeting(event)],
          todayAlreadyRang: true,
        );
        // The event's own day rang at 12:00: before the event for a gap
        // (the last minutes before midnight - nothing missed), after it for
        // an overlap (just after midnight - missed). On the neighbour the
        // verdict would be the opposite.
        expect(result.possiblyMissedAppointment, t.isOverlap,
            reason: '$t: appointment at ${_reads(event.millisecondsSinceEpoch)} '
                'is on ${isoDate(dEvent)}, not ${isoDate(neighbour)}');
      }
    }, skip: noDst);

    test('T13: the diagnostics minute and window-day index use the rules at '
        'the appointment', () async {
      Diag.setIncludeClockTimes(true);
      for (final t in transitions2026) {
        Diag.resetForTest();
        Diag.setIncludeClockTimes(true);
        final c = t11Case(t);
        await planAcross(t, c.event);
        final ringDay =
            dayMarker(localDateOfWall(t.instantMs + t.offsetAfterMs), -1);
        final records = Diag.records
            .where((r) => r.event == DiagEvent.dayEventTime)
            .toList();
        expect(records, hasLength(1), reason: '$t');
        expect(records.single.fields[DiagField.eventStartMinuteOfDay],
            c.minuteOfDay,
            reason: '$t: the appointment reads ${_reads(c.event.millisecondsSinceEpoch)}');
        expect(records.single.fields[DiagField.windowDayOffset],
            dayDistance(c.dAfter, ringDay),
            reason: '$t: it belongs to ${isoDate(c.dAfter)}');
      }
    }, skip: noDst);
  });

  // -------------------------------------------------------------------------
  // Stage S3 - process-zone twins (compile against 8ac1d9e)
  // -------------------------------------------------------------------------

  group('TW1: the real ring sequence across each transition reads 07:00', () {
    for (final (preferred, md) in [
      (const TimeOfDay(hour: 7, minute: 0), 15),
      (const TimeOfDay(hour: 7, minute: 0), 30),
      (null, 15),
      (null, 30),
    ]) {
      test('P $preferred, maxDailyDelta $md', () async {
        for (final t in transitions2026) {
          final d07 = _d07(t);
          final start = dayMarker(d07, -3);
          final appState =
              await _freshAppState(preferred: preferred, maxDeltaMinutes: md);
          appState.lastProcessedConcludedDay = start;
          appState.pendingDayValues = {
            isoDate(start): _at(start, 7, 0).millisecondsSinceEpoch,
          };
          for (var k = 0; k <= 6; k++) {
            final day = dayMarker(start, k);
            final now = _local(appState.pendingDayValues[isoDate(day)]!);
            final result = await replan(
              appState,
              now: () => now,
              fetchEvents: (from, to) async => [],
              todayAlreadyRang: true,
            );
            final next = dayMarker(day, 1);
            final value = appState.pendingDayValues[isoDate(next)];
            expect(_readsOn(value, next, 7, 0), isTrue,
                reason: '$t: ${isoDate(next)} reads '
                    '${value == null ? null : _reads(value)}, not 07:00');
            expect(result.overrunNotificationNeeded, isFalse,
                reason: '$t: a DST change is not a shift (${isoDate(next)})');
          }
        }
      }, skip: noDst);
    }
  });

  test('TW3: the transition on every window position reads 07:00 (P 07:00, '
      'md 15)', () async {
    for (final t in transitions2026) {
      final d07 = _d07(t);
      for (var k = 0; k <= 6; k++) {
        final concluded = dayMarker(d07, -k - 1);
        final appState = await _freshAppState(
            preferred: const TimeOfDay(hour: 7, minute: 0), maxDeltaMinutes: 15);
        final rang = _at(concluded, 7, 0);
        appState.lastProcessedConcludedDay = concluded;
        appState.pendingDayValues = {isoDate(concluded): rang.millisecondsSinceEpoch};
        await replan(
          appState,
          now: () => rang,
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: true,
        );
        for (var i = 1; i <= 7; i++) {
          final day = dayMarker(concluded, i);
          final value = appState.pendingDayValues[isoDate(day)];
          expect(_readsOn(value, day, 7, 0), isTrue,
              reason: '$t, k $k: ${isoDate(day)} reads '
                  '${value == null ? null : _reads(value)}');
        }
      }
    }
  }, skip: noDst);

  test('TW5: a recovery replan after the change reads the anchor with its own '
      'offset (P 07:00, md 15)', () async {
    for (final t in transitions2026) {
      final d07 = _d07(t);
      final before = dayMarker(d07, -1);
      final rang = _at(before, 7, 0);
      final appState = await _freshAppState(
          preferred: const TimeOfDay(hour: 7, minute: 0), maxDeltaMinutes: 15);
      appState.lastProcessedConcludedDay = before;
      appState.lastReplanDate = before;
      appState.pendingDayValues = {isoDate(before): rang.millisecondsSinceEpoch};

      // The premise (G#13): without it the plan would go through the cold
      // start and pass for the wrong reason.
      expect(appState.pendingDayValues[isoDate(before)],
          rang.millisecondsSinceEpoch);
      expect(isoDate(appState.lastProcessedConcludedDay!), isoDate(before));

      await replan(
        appState,
        now: () => _at(d07, 6, 30),
        fetchEvents: (from, to) async => [],
        todayAlreadyRang: false,
      );

      expect(appState.pendingDayValues[isoDate(before)],
          rang.millisecondsSinceEpoch,
          reason: '$t: premise - the anchor is the rung value');
      expect(isoDate(appState.lastProcessedConcludedDay!), isoDate(before),
          reason: '$t: premise - the recovery concluded nothing new');
      final value = appState.pendingDayValues[isoDate(d07)];
      expect(_readsOn(value, d07, 7, 0), isTrue,
          reason: '$t: ${isoDate(d07)} reads '
              '${value == null ? null : _reads(value)}');
    }
  }, skip: noDst);

  test('TW8b: a held reading in the gap survives a ring through persistence '
      '(P null, md 30)', () async {
    for (final t in gaps2026) {
      final w = t.wallMiddleMs;
      final f = wallFields(w);
      final dw = localDateOfWall(w);
      final before = dayMarker(dw, -1);
      final rang = _at(before, f.hour, f.minute);
      final appState = await _freshAppState();
      appState.lastProcessedConcludedDay = before;
      appState.pendingDayValues = {isoDate(before): rang.millisecondsSinceEpoch};

      // Ring 1: the day before the gap rings; the gap day is planned.
      await replan(appState,
          now: () => rang,
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: true);
      final vDw = appState.pendingDayValues[isoDate(dw)];
      expect(vDw, expectedPlannedInstantMs(transitions, w),
          reason: '$t: ${isoDate(dw)} ${f.hour}:${f.minute} is skipped -> '
              'R_plan ${_reads(expectedPlannedInstantMs(transitions, w))}, got '
              '${vDw == null ? null : _reads(vDw)}');
      expect(appState.pendingDayClockTimes[isoDate(dw)],
          (clockTime: w, value: vDw),
          reason: '$t: the planned clock time is persisted with its value');

      // Ring 2: the gap day rings; the next day continues from the planned
      // clock time, not from what the clock showed.
      await replan(appState,
          now: () => _local(vDw!),
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: true);
      final next = dayMarker(dw, 1);
      final vNext = appState.pendingDayValues[isoDate(next)];
      expect(_readsOn(vNext, next, f.hour, f.minute), isTrue,
          reason: '$t: ${isoDate(next)} reads '
              '${vNext == null ? null : _reads(vNext)}, not the planned '
              '${f.hour}:${f.minute}');
    }
  }, skip: gaps2026.isEmpty ? noTransitionReason : false);

  test('T32p: checkpoint 2 with a stale baseline leaves the resolved plan '
      'alone (process zone)', () async {
    for (final t in transitions2026) {
      final d07 = _d07(t);
      final start = dayMarker(d07, -2);
      final appState = await _freshAppState(
          preferred: const TimeOfDay(hour: 7, minute: 0));
      appState.lastProcessedConcludedDay = start;
      appState.pendingDayValues = {
        isoDate(start): _at(start, 7, 0).millisecondsSinceEpoch,
      };
      for (final day in [start, dayMarker(start, 1)]) {
        final now = _local(appState.pendingDayValues[isoDate(day)]!);
        await replan(appState,
            now: () => now,
            fetchEvents: (from, to) async => [],
            todayAlreadyRang: true);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'lastCheckedUtcOffsetMinutes', t.offsetBeforeMs ~/ _minuteMs);
      final planned = _json(prefs, 'pendingDayValues');

      await runTimezoneCheckpoint2(
          prefs: prefs, now: () => _local(t.instantMs + 30 * _minuteMs));

      final after = _json(prefs, 'pendingDayValues');
      expect(_readsOn(after[isoDate(d07)] as int?, d07, 7, 0), isTrue,
          reason: '$t: ${isoDate(d07)} must read 07:00');
      for (var i = 0; i < 7; i++) {
        final day = isoDate(dayMarker(d07, i));
        expect(after[day], planned[day],
            reason: '$t: checkpoint 2 moved $day from '
                '${planned[day] == null ? null : _reads(planned[day] as int)} '
                'to ${after[day] == null ? null : _reads(after[day] as int)}');
      }
      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'),
          t.offsetAfterMs ~/ _minuteMs);
    }
  }, skip: noDst);

  // -------------------------------------------------------------------------
  // Stage S3 - T54: America/Nuuk's gap ending at midnight (TZ-2a)
  // -------------------------------------------------------------------------

  final laterDateGaps = gaps2026
      .where((t) => resolvesOntoLaterDate(t, t.wallMiddleMs))
      .toList();

  test('T54: a skipped 23:30 rings at 22:59 on its own planned day; that day '
      'is the rung day and the FR-21 key', () async {
    for (final t in laterDateGaps) {
      final w = t.wallMiddleMs;
      final f = wallFields(w);
      final dw = localDateOfWall(w);
      final before = dayMarker(dw, -1);
      final next = dayMarker(dw, 1);
      final rang = _at(before, f.hour, f.minute);
      final appState = await _freshAppState();
      appState.lastProcessedConcludedDay = before;
      appState.pendingDayValues = {isoDate(before): rang.millisecondsSinceEpoch};

      // (1) The day before rings: the gap day is planned one minute before
      // the gap, on its own date.
      await replan(appState,
          now: () => rang,
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: true);
      final expected = t.instantMs - _minuteMs;
      expect(appState.pendingDayValues[isoDate(dw)], expected,
          reason: '$t: expected ${_reads(expected)}, got '
              '${_reads(appState.pendingDayValues[isoDate(dw)]!)}');
      final alarm = appState.scheduledAlarms.singleWhere(
          (a) => a.time.millisecondsSinceEpoch == expected,
          orElse: () => fail('$t: no ScheduledAlarm at ${_reads(expected)}'));
      expect(isoDate(alarm.time), isoDate(dw));

      // (2) FR-21: switching that alarm's day off switches off the planned
      // day - not the next one.
      appState.setDayEnabled(isoDate(alarm.time), false);
      await replan(appState,
          now: () => _at(dw, 12, 0),
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: false);
      expect(appState.disabledDays, contains(isoDate(dw)));
      expect(appState.disabledDays, isNot(contains(isoDate(next))));
      expect(
          appState.scheduledAlarms
              .where((a) => a.time.millisecondsSinceEpoch == expected),
          isEmpty,
          reason: '$t: the switched-off day must not be armed');
      expect(
          appState.scheduledAlarms.where((a) => isoDate(a.time) == isoDate(next)),
          isNotEmpty,
          reason: '$t: the next day stays armed');
      appState.setDayEnabled(isoDate(dw), true);
      await replan(appState,
          now: () => _at(dw, 12, 0),
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: false);
      expect(appState.pendingDayValues[isoDate(dw)], expected);
      expect(
          appState.scheduledAlarms
              .where((a) => a.time.millisecondsSinceEpoch == expected),
          isNotEmpty,
          reason: '$t: switched back on, the planned day is armed again');

      // (3) It rings (22:59 on the planned day): that day is the rung day,
      // and the next day holds the planned 23:30, not 22:59.
      await replan(appState,
          now: () => _local(expected),
          fetchEvents: (from, to) async => [],
          todayAlreadyRang: true);
      expect(isoDate(appState.lastProcessedConcludedDay!), isoDate(dw));
      expect(appState.pendingDayValues[isoDate(dw)], expected);
      final vNext = appState.pendingDayValues[isoDate(next)];
      expect(_readsOn(vNext, next, f.hour, f.minute), isTrue,
          reason: '$t: ${isoDate(next)} reads '
              '${vNext == null ? null : _reads(vNext)}');
    }
  },
      skip: laterDateGaps.isEmpty
          ? 'no gap in the process zone resolves onto a later date (only '
              'America/Nuuk, Godthab, Scoresbysund have one, 2026/27)'
          : false);

  // -------------------------------------------------------------------------
  // Stage S3 - injected cases
  // -------------------------------------------------------------------------

  /// Requirements T32's replan: ring on Sat 28 Mar 2026 07:00 CET (06:00
  /// UTC), Europe/Berlin rules injected.
  Future<AppState> planOnSaturday({
    List<Meeting> events = const [],
    bool scheduleOnGapDays = true,
    Map<String, Object> prefs = const {},
  }) async {
    final appState = await _freshAppState(
        prefs: prefs, preferred: const TimeOfDay(hour: 7, minute: 0));
    appState.scheduleOnGapDays = scheduleOnGapDays;
    appState.lastProcessedConcludedDay = DateTime(2026, 3, 27);
    appState.pendingDayValues = {
      '2026-03-27': _ms(3, 27, 6),
      '2026-03-28': _ms(3, 28, 6),
    };
    await replan(
      appState,
      now: () => tz.TZDateTime(berlin, 2026, 3, 28, 7, 0),
      offsetAt: berlinRules,
      fetchEvents: (from, to) async => events,
      todayAlreadyRang: true,
    );
    return appState;
  }

  Map<String, Object> clockTimeEntry(int month, int day, int hour, int value) =>
      {'c': DateTime.utc(2026, month, day, hour).millisecondsSinceEpoch, 'v': value};

  group('T33: pendingDayClockTimes is merged and pruned by replan', () {
    test('entries before the retention bound dropped, outside-window days '
        'kept, window days replaced; written as the value\'s pair', () async {
      final appState = await planOnSaturday(prefs: {
        'pendingDayClockTimes': jsonEncode({
          '2026-03-20': clockTimeEntry(3, 20, 7, _ms(3, 20, 6)),
          '2026-03-27': clockTimeEntry(3, 27, 7, _ms(3, 27, 6)),
          '2026-03-28': clockTimeEntry(3, 28, 7, _ms(3, 28, 6)),
          '2026-03-30': clockTimeEntry(3, 30, 9, _ms(3, 30, 7)),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final stored = _json(prefs, 'pendingDayClockTimes');
      // The same bound as pendingDayValues/pendingDayInstantAnchored: the
      // day before the concluded day.
      expect(stored.containsKey('2026-03-20'), isFalse);
      expect(appState.pendingDayValues.containsKey('2026-03-20'), isFalse);
      expect(stored['2026-03-27'], clockTimeEntry(3, 27, 7, _ms(3, 27, 6)));
      expect(stored['2026-03-28'], clockTimeEntry(3, 28, 7, _ms(3, 28, 6)));
      for (var d = 29; d <= 35; d++) {
        final day = DateTime.utc(2026, 3, d);
        final key = isoDate(day);
        expect(stored[key], clockTimeEntry(day.month, day.day, 7, _ms(day.month, day.day, 5)),
            reason: '$key: replaced by the fresh plan (07:00 = 05:00 UTC)');
        expect((stored[key] as Map)['v'], appState.pendingDayValues[key]);
      }
      expect(appState.pendingDayClockTimes['2026-03-29'],
          (clockTime: DateTime.utc(2026, 3, 29, 7).millisecondsSinceEpoch,
           value: _ms(3, 29, 5)));
    });

    test('a window day that becomes instant-anchored or null loses its entry',
        () async {
      final appState = await planOnSaturday();
      final prefs = await SharedPreferences.getInstance();
      expect(_json(prefs, 'pendingDayClockTimes').keys,
          containsAll(['2026-03-30', '2026-03-31', '2026-04-01']));

      // Same state, replanned (settings change) with gap days masked and an
      // appointment at Tue 31 Mar 05:00 CEST (03:00 UTC), before 07:00.
      appState.scheduleOnGapDays = false;
      await replan(
        appState,
        now: () => tz.TZDateTime(berlin, 2026, 3, 28, 12, 0),
        offsetAt: berlinRules,
        fetchEvents: (from, to) async => [
          _meeting(DateTime.utc(2026, 3, 30, 5, 30)), // Mon 07:30 CEST
          _meeting(DateTime.utc(2026, 3, 31, 3, 0)), // Tue 05:00 CEST
        ],
      );
      final stored = _json(prefs, 'pendingDayClockTimes');
      expect(appState.pendingDayInstantAnchored['2026-03-31'], isTrue);
      expect(stored.containsKey('2026-03-31'), isFalse,
          reason: 'instant-anchored: no planned clock time');
      expect(appState.pendingDayValues['2026-04-01'], isNull);
      expect(stored.containsKey('2026-04-01'), isFalse,
          reason: 'no value: no planned clock time');
      // Monday keeps a paired entry, but not 07:00: from Saturday's 07:00
      // anchor, holding cannot reach Tuesday's 05:00 cap within
      // maxDailyDelta (120 min over two days at 30 min/day), so FR-7 starts
      // a run on Sunday with three 40-minute steps on readings:
      // Sun 06:20, Mon 05:40, Tue capped at 05:00 (instant-anchored).
      final monday = <String, Object>{
        'c': DateTime.utc(2026, 3, 30, 5, 40).millisecondsSinceEpoch,
        'v': _ms(3, 30, 3, 40), // 05:40 CEST
      };
      expect(stored['2026-03-30'], monday);
      expect((stored['2026-03-30'] as Map)['v'],
          appState.pendingDayValues['2026-03-30']);
    });

    test('the key is written by every replan, {} when nothing is '
        'wall-clock-anchored', () async {
      final appState = await _freshAppState();
      await replan(
        appState,
        now: () => tz.TZDateTime(berlin, 2026, 3, 28, 7, 0),
        offsetAt: berlinRules,
        fetchEvents: (from, to) async => [],
        todayAlreadyRang: true,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pendingDayClockTimes'), '{}');
    });
  });

  group('checkpoint 2 policy (T206-R14)', () {
    /// T32's state as T-206 plans it (see replan_test.dart's FR-16 bullets).
    Map<String, Object> plannedState({
      Map<String, int> values = const {},
      Object? clockTimes,
      bool withClockTimesKey = true,
    }) {
      final days = [for (var d = 29; d <= 35; d++) DateTime.utc(2026, 3, d)];
      return {
        'lastCheckedUtcOffsetMinutes': 60,
        'pendingDayValues': jsonEncode({
          '2026-03-28': _ms(3, 28, 6),
          for (final d in days) isoDate(d): _ms(d.month, d.day, 5),
          ...values,
        }),
        'pendingDayInstantAnchored': jsonEncode({
          '2026-03-28': false,
          for (final d in days) isoDate(d): false,
        }),
        if (withClockTimesKey)
          'pendingDayClockTimes': clockTimes is String
              ? clockTimes
              : jsonEncode(clockTimes ??
                  {
                    for (final d in days)
                      isoDate(d):
                          clockTimeEntry(d.month, d.day, 7, _ms(d.month, d.day, 5)),
                  }),
      };
    }

    DateTime sunday0330() => tz.TZDateTime(berlin, 2026, 3, 29, 3, 30);

    test('T43: travel semantics - an intact entry re-resolves to the same '
        'instant the legacy shift gives, and its paired value follows', () async {
      final value = DateTime.utc(2026, 3, 11, 8, 0).millisecondsSinceEpoch;
      final expected = DateTime.utc(2026, 3, 11, 0, 0).millisecondsSinceEpoch;
      for (final (label, rules) in [
        ('fixed +9', fixedOffset(const Duration(hours: 9))),
        ('Asia/Tokyo rules', zoneRules(tz.getLocation('Asia/Tokyo'))),
      ]) {
        SharedPreferences.setMockInitialValues({
          'lastCheckedUtcOffsetMinutes': 60,
          'pendingDayValues': jsonEncode({'2026-03-11': value}),
          'pendingDayInstantAnchored': jsonEncode({'2026-03-11': false}),
          'pendingDayClockTimes':
              jsonEncode({'2026-03-11': clockTimeEntry(3, 11, 9, value)}),
        });
        final prefs = await SharedPreferences.getInstance();
        await runTimezoneCheckpoint2(
            offsetAt: rules,
            prefs: prefs,
            now: () => DateTime.utc(2026, 3, 10, 13, 0));
        expect(_json(prefs, 'pendingDayValues')['2026-03-11'], expected,
            reason: label);
        expect(_json(prefs, 'pendingDayClockTimes')['2026-03-11'],
            clockTimeEntry(3, 11, 9, expected),
            reason: label);
      }
    });

    test('T44: FR-11 - a rung day and its entry survive both checkpoint 2 '
        'runs; a value that has just rung is not touched', () async {
      SharedPreferences.setMockInitialValues(plannedState(clockTimes: {
        '2026-03-28': clockTimeEntry(3, 28, 7, _ms(3, 28, 6)),
        for (var d = 29; d <= 35; d++)
          isoDate(DateTime.utc(2026, 3, d)): clockTimeEntry(
              DateTime.utc(2026, 3, d).month,
              DateTime.utc(2026, 3, d).day,
              7,
              _ms(DateTime.utc(2026, 3, d).month, DateTime.utc(2026, 3, d).day, 5)),
      }));
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
          offsetAt: berlinRules, prefs: prefs, now: sunday0330);
      expect(_json(prefs, 'pendingDayValues')['2026-03-28'], _ms(3, 28, 6));
      expect(_json(prefs, 'pendingDayClockTimes')['2026-03-28'],
          clockTimeEntry(3, 28, 7, _ms(3, 28, 6)));
      final sundayAfterFirst = _json(prefs, 'pendingDayValues')['2026-03-29'];

      // Sun 07:30 CEST: Sunday's 07:00 has rung. A change is detected again.
      await prefs.setInt('lastCheckedUtcOffsetMinutes', 60);
      await runTimezoneCheckpoint2(
          offsetAt: berlinRules,
          prefs: prefs,
          now: () => tz.TZDateTime(berlin, 2026, 3, 29, 7, 30));
      expect(_json(prefs, 'pendingDayValues')['2026-03-28'], _ms(3, 28, 6));
      expect(_json(prefs, 'pendingDayClockTimes')['2026-03-28'],
          clockTimeEntry(3, 28, 7, _ms(3, 28, 6)));
      expect(_json(prefs, 'pendingDayValues')['2026-03-29'], sundayAfterFirst,
          reason: 'Sunday is past: FR-11');
    });

    for (final (label, state, expectedSunday) in [
      (
        '(b) the stored value differs from the entry\'s paired value',
        () => plannedState(values: {'2026-03-29': _ms(3, 29, 6)}),
        _ms(3, 29, 6),
      ),
      (
        '(c) the key exists but has no entry for the day',
        () => plannedState(clockTimes: {
              '2026-03-30': clockTimeEntry(3, 30, 7, _ms(3, 30, 5)),
            }),
        _ms(3, 29, 5),
      ),
      (
        '(d) the key holds unreadable JSON',
        () => plannedState(clockTimes: '{"2026-03-29": {"c": '),
        _ms(3, 29, 5),
      ),
    ]) {
      test('T48 torn pair $label: the day is left untouched', () async {
        SharedPreferences.setMockInitialValues(state());
        final prefs = await SharedPreferences.getInstance();
        await runTimezoneCheckpoint2(
            offsetAt: berlinRules, prefs: prefs, now: sunday0330);
        expect(_json(prefs, 'pendingDayValues')['2026-03-29'], expectedSunday);
        expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 120);
      });
    }

    test('T50: legacy branch - with no pendingDayClockTimes key at all (a plan '
        'from before T-206) the old shift still applies', () async {
      SharedPreferences.setMockInitialValues(
          plannedState(withClockTimesKey: false));
      final prefs = await SharedPreferences.getInstance();
      await runTimezoneCheckpoint2(
          offsetAt: berlinRules, prefs: prefs, now: sunday0330);
      // 05:00 UTC shifted by (+1 - +2) = 04:00 UTC. This is why a PRESENT
      // but empty key must not fall back to the legacy shift (T48 (c)).
      expect(_json(prefs, 'pendingDayValues')['2026-03-29'], _ms(3, 29, 4));
      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 120);
    });
  });

  group('T51: the gap-day mask and FR-21 keep value and clock time together',
      () {
    test('scheduleOnGapDays = false: masked days get no pendingDayClockTimes '
        'entry', () async {
      final appState = await planOnSaturday(scheduleOnGapDays: false, events: [
        _meeting(DateTime.utc(2026, 3, 30, 5, 30)), // Mon 07:30 CEST
        _meeting(DateTime.utc(2026, 4, 2, 5, 30)), // Thu 07:30 CEST
      ]);
      final prefs = await SharedPreferences.getInstance();
      final stored = _json(prefs, 'pendingDayClockTimes');
      for (final key in [
        '2026-03-29',
        '2026-03-31',
        '2026-04-01',
        '2026-04-03',
        '2026-04-04',
      ]) {
        expect(appState.pendingDayValues[key], isNull, reason: key);
        expect(stored.containsKey(key), isFalse, reason: key);
      }
      expect(stored['2026-03-30'], clockTimeEntry(3, 30, 7, _ms(3, 30, 5)));
      expect(stored['2026-04-02'], clockTimeEntry(4, 2, 7, _ms(4, 2, 5)));
    });

    test('FR-21: switching Sun 29 Mar off and on changes neither its value nor '
        'its planned clock time; switched on, it is armed at 05:00 UTC',
        () async {
      final appState = await planOnSaturday();
      final prefs = await SharedPreferences.getInstance();
      expect(appState.pendingDayValues['2026-03-29'], _ms(3, 29, 5));
      final entry = _json(prefs, 'pendingDayClockTimes')['2026-03-29'];
      expect(entry, clockTimeEntry(3, 29, 7, _ms(3, 29, 5)));

      for (final enabled in [false, true]) {
        appState.setDayEnabled('2026-03-29', enabled);
        await replan(
          appState,
          now: () => tz.TZDateTime(berlin, 2026, 3, 28, 12, 0),
          offsetAt: berlinRules,
          fetchEvents: (from, to) async => [],
        );
        expect(appState.pendingDayValues['2026-03-29'], _ms(3, 29, 5),
            reason: 'enabled $enabled');
        expect(_json(prefs, 'pendingDayClockTimes')['2026-03-29'], entry,
            reason: 'enabled $enabled');
      }
      expect(
          appState.scheduledAlarms
              .where((a) => a.time.millisecondsSinceEpoch == _ms(3, 29, 5)),
          isNotEmpty);
    });
  });

  test('T56: the diagnostics step is measured on readings - a plan holding '
      '07:00 across the change logs a zero step', () async {
    final appState = await _freshAppState();
    appState.lastProcessedConcludedDay = DateTime(2026, 3, 26);
    appState.pendingDayValues = {'2026-03-27': _ms(3, 27, 6)};
    await replan(
      appState,
      now: () => tz.TZDateTime(berlin, 2026, 3, 27, 7, 0),
      offsetAt: berlinRules,
      fetchEvents: (from, to) async => [],
      todayAlreadyRang: true,
    );
    // The premise: the plan really holds 07:00 by the clock (06:00 UTC on
    // Saturday, 05:00 UTC from Sunday) - without it a zero step would be
    // the one-offset plan's, for the wrong reason.
    expect(appState.pendingDayValues['2026-03-28'], _ms(3, 28, 6));
    expect(appState.pendingDayValues['2026-03-29'], _ms(3, 29, 5));
    final record = Diag.records
        .lastWhere((r) => r.event == DiagEvent.weekPlanComputed);
    expect(record.fields[DiagField.maxStepBucket], MinuteBucket.zero.code,
        reason: 'a DST change is not a 60-minute step');
  });
}
