import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'support/zone_rules.dart';

// Phase 4 (docs/scheduling-v2-spec.md, "Implementation order"):
// replan(AppState) - T-60 (calendar cache bypass), FR-11, FR-12, FR-15.
// The trigger layer above this (FR-16 checkpoint 1, FR-17, T-65) lives in
// test/checkpoint_test.dart. fetchEvents/now/deviceUtcOffset are injected
// everywhere so these
// tests never touch the real device_calendar plugin or the ambient system
// clock/timezone (same testability rationale as FR-2's deviceUtcOffset
// parameter, see scheduling_v2_test.dart).

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

Meeting _meetingAt(DateTime from, {String? id}) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
      ids: id == null ? const [] : [id],
    );

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  group('replan (FR-8/T-60/FR-11/FR-12/FR-15)', () {
    test(
        'cold start: the first replan() without preferredWakeUpTime plans nothing before the first hardFloor',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      final result = await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 30, day: 16))],
      );

      // window = windowStart(=ringDay+1=day 11)..day 17.
      expect(appState.pendingDayValues['2026-03-11'], isNull);
      expect(appState.pendingDayValues['2026-03-16'],
          _utc(5, 30, day: 16).millisecondsSinceEpoch);
      expect(appState.lastReplanDate, ringDay);
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);
      expect(result.possiblyMissedAppointment, isFalse);
    });

    test(
        'T-60: two replan() calls on the same day with different calendar data - the second one wins (FR-11)',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
      );
      final firstValue = appState.pendingDayValues['2026-03-11'];
      final counterAfterFirst = appState.gapDayCounter;

      // Same day, but the calendar data has changed (e.g. a new appointment
      // appeared) - no process restart needed to simulate that, just a
      // second replan() call with different fake data.
      final result = await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [_meetingAt(_utc(6, 0, day: 11))],
      );

      expect(appState.pendingDayValues['2026-03-11'], isNot(firstValue));
      expect(appState.pendingDayValues['2026-03-11'],
          _utc(6, 0, day: 11).millisecondsSinceEpoch);
      // gapDayCounter must not be advanced twice by the second call on the
      // same day.
      expect(appState.gapDayCounter, counterAfterFirst);
      expect(result.possiblyMissedAppointment, isFalse);
    });

    test(
        'FR-12: an appointment discovered late for the already-rung day triggers possiblyMissedAppointment, without changing its fixed value',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      // First checkpoint (day 9 rings): calendar completely empty -> cold
      // start with preferredWakeUpTime, day 10 (windowStart) is set to
      // 07:00 and is from now on the fixed, actually-rung value.
      await replan(
        appState,
        now: () => _utc(0, 0, day: 9),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
      );
      expect(appState.pendingDayValues['2026-03-10'],
          _utc(7, 0, day: 10).millisecondsSinceEpoch);

      // Second checkpoint (day 10 rings): the calendar re-read now
      // discovers, late, a real appointment FOR day 10 itself (which has
      // already rung) with a stricter hardFloor (05:00) than the value
      // actually used (07:00).
      final result = await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 10))],
        // This scenario is the ring checkpoint: day 10 has rung, so it's
        // concluded (docs/TODO.md T-71).
        todayAlreadyRang: true,
      );

      expect(result.possiblyMissedAppointment, isTrue);
      // FR-12: "the rung value stays unchanged".
      expect(appState.pendingDayValues['2026-03-10'],
          _utc(7, 0, day: 10).millisecondsSinceEpoch);
    });

    // FR-12 false positive (device report, 2026-10-04): scheduled alarms
    // switched off (FR-21) for Thursday and Friday, the app not opened until
    // Sunday evening - opening it produced "A newly-added appointment may not
    // have been accounted for by your last alarm." FR-12 is about a day whose
    // alarm RANG ("after a day's alarm has rung"); a switched-off day had no
    // alarm that could have missed anything.
    group('FR-12: only a day whose alarm could have rung is checked', () {
      // Wed 11 Mar rings: an empty calendar, preferredWakeUpTime 07:00 ->
      // Thu 12 .. Wed 18 planned at 07:00.
      Future<AppState> plannedWeek({bool scheduleOnGapDays = true}) async {
        final appState = await _freshAppState();
        appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
        appState.scheduleOnGapDays = scheduleOnGapDays;
        await replan(
          appState,
          now: () => _utc(7, 0, day: 11),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        return appState;
      }

      // Sun 15 Mar, 20:00: the app is opened (FR-17; Sunday's 07:00 has
      // rung by then, but no ring checkpoint ran - so this is the day
      // advance over Thu..Sat). Appointments for Thu and Fri at 05:00 were
      // entered after Wednesday's plan.
      Future<ReplanResult> openOnSundayEvening(AppState appState,
              List<Meeting> events) =>
          replan(
            appState,
            now: () => _utc(20, 0, day: 15),
            offsetAt: fixedOffset(Duration.zero),
            fetchEvents: (start, end) async => events,
          );

      final lateThuFri = [
        _meetingAt(_utc(5, 0, day: 12)),
        _meetingAt(_utc(5, 0, day: 13)),
      ];

      test('switched-off days are not reported', () async {
        final appState = await plannedWeek();
        expect(appState.pendingDayValues['2026-03-12'],
            _utc(7, 0, day: 12).millisecondsSinceEpoch);
        appState.setDayEnabled('2026-03-12', false);
        appState.setDayEnabled('2026-03-13', false);

        final result = await openOnSundayEvening(appState, lateThuFri);

        expect(result.possiblyMissedAppointment, isFalse,
            reason: 'Thursday and Friday were switched off - no alarm rang');
      });

      test('counter-test: a day with no planned value is still reported',
          () async {
        // scheduleOnGapDays off: an appointment-free day gets no alarm at
        // all (T-52.1), so Thursday and Friday have no value. An appointment
        // that surfaces for such a day later is still worth the warning -
        // only switched-off days are excluded (the device report was about
        // those; narrowing further needs the maintainer's decision).
        final appState = await plannedWeek(scheduleOnGapDays: false);
        expect(appState.pendingDayValues['2026-03-12'], isNull);

        final result = await openOnSundayEvening(appState, lateThuFri);

        expect(result.possiblyMissedAppointment, isTrue);
      });

      test('counter-test: a late appointment on a day that rang still is',
          () async {
        final appState = await plannedWeek();
        appState.setDayEnabled('2026-03-12', false);
        appState.setDayEnabled('2026-03-13', false);

        // Saturday was not switched off; its 07:00 rang, and a 05:00
        // appointment entered later would have needed an earlier alarm.
        final result = await openOnSundayEvening(
            appState, [...lateThuFri, _meetingAt(_utc(5, 0, day: 14))]);

        expect(result.possiblyMissedAppointment, isTrue);
      });
    });

    test(
        'a multi-day gap (e.g. a reboot): gapDayCounter is advanced individually for each skipped day',
        () async {
      final appState = await _freshAppState();

      await replan(
        appState,
        now: () => _utc(0, 0, day: 9),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );
      expect(appState.gapDayCounter, 1); // day 9 itself: no appointment.

      // A 3-day gap (day 10, 11, 12 never processed individually) - all 3
      // with no appointment.
      await replan(
        appState,
        now: () => _utc(0, 0, day: 12),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );
      expect(appState.gapDayCounter, 4); // 1 (day 9) + 3 (day 10,11,12).
    });

    // docs/TODO.md T-82: the merge without pruning was load-bearing for
    // *today* (see the comment at the merge point), but nothing was ever
    // removed - after a year, ~365 entries sit in a JSON string that every
    // replan decodes, copies, and re-encodes.
    group('T-82: old entries are bounded', () {
      test('entries before yesterday disappear, yesterday and today stay',
          () async {
        final appState = await _freshAppState();
        appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
        appState.pendingDayValues = {
          '2025-01-01': DateTime.utc(2025, 1, 1, 7).millisecondsSinceEpoch,
          '2026-02-14': DateTime.utc(2026, 2, 14, 7).millisecondsSinceEpoch,
          '2026-03-08': _utc(7, 0, day: 8).millisecondsSinceEpoch,
          '2026-03-09': _utc(7, 0, day: 9).millisecondsSinceEpoch,
          '2026-03-10': _utc(7, 0, day: 10).millisecondsSinceEpoch,
        };

        // Ring on day 10 -> lastConcludedDay = day 10, boundary = day 9.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );

        expect(appState.pendingDayValues.containsKey('2025-01-01'), isFalse);
        expect(appState.pendingDayValues.containsKey('2026-02-14'), isFalse);
        expect(appState.pendingDayValues.containsKey('2026-03-08'), isFalse);
        // Yesterday and today stay - today is the anchor of the next
        // window and still carries an open alarm until it rings.
        expect(appState.pendingDayValues.containsKey('2026-03-09'), isTrue);
        expect(appState.pendingDayValues.containsKey('2026-03-10'), isTrue);
        // And the entire new window.
        expect(appState.pendingDayValues.containsKey('2026-03-17'), isTrue);
        expect(appState.pendingDayValues.length, 9);
      });

      test('the map does not keep growing across many replans', () async {
        final appState = await _freshAppState();
        appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

        for (var d = 10; d <= 25; d++) {
          await replan(
            appState,
            now: () => _utc(7, 0, day: d),
            offsetAt: fixedOffset(Duration.zero),
            fetchEvents: (start, end) async => [],
            todayAlreadyRang: true,
          );
        }

        // 7 window days + yesterday + today; never more, no matter how long
        // the app has been running.
        expect(appState.pendingDayValues.length, lessThanOrEqualTo(9));
        expect(appState.pendingDayInstantAnchored.length,
            lessThanOrEqualTo(9),
            reason: 'the anchor map must not grow separately from it');
      });

      test('today\'s not-yet-rung value stays on a recovery replan',
          () async {
        // The case the prune must not break under any circumstances: today
        // 07:00 is planned, a recovery checkpoint runs at 03:00. If today's
        // entry dropped out, FR-18 would remove the alarm.
        final appState = await _freshAppState();
        appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
        appState.pendingDayValues = {
          '2026-03-10': _utc(7, 0, day: 10).millisecondsSinceEpoch,
        };

        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
        );

        expect(appState.pendingDayValues['2026-03-10'], isNotNull);
      });
    });

    // docs/TODO.md T-78 / FR-9 "exception: preferredWakeUpTime set": the
    // end state that's really at stake here - a user with no calendar
    // appointments, but with a preferred wake-up time, must not end up
    // without an alarm after two weeks.
    test('T-78: a preferredWakeUpTime user with no appointments keeps alarms even after 14 days',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      for (var d = 9; d <= 22; d++) {
        await replan(
          appState,
          now: () => _utc(7, 0, day: d),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
      }

      // The counter keeps honestly counting appointment-free days ...
      expect(appState.gapDayCounter, greaterThanOrEqualTo(7));
      // ... but a value is still planned for every window day.
      final windowValues = [23, 24, 25, 26, 27, 28, 29]
          .map((d) => appState.pendingDayValues['2026-03-$d'])
          .toList();
      expect(windowValues.every((v) => v != null), isTrue,
          reason: 'no window day may be empty, got $windowValues');
      expect(windowValues.first, _utc(7, 0, day: 23).millisecondsSinceEpoch);
    });

    // docs/TODO.md T-75: `lastReplanDate` carried two meanings at once -
    // FR-17's daily lock ("already replanned today?") AND the day-advance's
    // progress ("up to which concluded day has it counted?"). Since T-71,
    // `lastConcludedDay` is today or yesterday depending on the trigger, but
    // `lastReplanDate` was always set to today: a recovery replan (an app
    // resume or a setting change before the morning alarm - a completely
    // normal occurrence) thus consumed the marker without advancing, and the
    // later real ring on the same day found `needsDayAdvance == false`. The
    // day was permanently lost: FR-9 undercounts, FR-12 never reports.
    group('T-75: two replans in one day', () {
      test('recovery on day D, then a ring on day D -> day D is still counted',
          () async {
        final appState = await _freshAppState();

        // Day 9 rings.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 9),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.gapDayCounter, 1);

        // Day 10, 03:00 at night: the app is opened (FR-17 recovery). Today
        // has not rung yet, so it must not be counted - day 9 has already
        // been processed, and correctly no advance happens here.
        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
        );
        expect(appState.gapDayCounter, 1,
            reason: 'the recovery itself must not count today (FR-9)');

        // Day 10, 07:00: the real alarm rings. NOW day 10 is concluded and
        // must be counted.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.gapDayCounter, 2,
            reason: 'day 9 and day 10 are both concluded and appointment-free');
      });

      test('FR-12 stays able to report after a recovery on the same day', () async {
        final appState = await _freshAppState();
        appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

        // Day 9 rings, empty calendar -> day 10 is planned at 07:00.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 9),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.pendingDayValues['2026-03-10'],
            _utc(7, 0, day: 10).millisecondsSinceEpoch);

        // Recovery at 03:00 on day 10, calendar still empty.
        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
        );

        // Day 10 rings at 07:00, and only now is the 05:00 appointment
        // known - so the alarm missed it.
        final result = await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 10))],
          todayAlreadyRang: true,
        );

        expect(result.possiblyMissedAppointment, isTrue);
      });

      test('FR-17\'s daily lock stays unaffected by this', () async {
        final appState = await _freshAppState();

        // A ring on day 9 sets both markers.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 9),
          offsetAt: fixedOffset(Duration.zero),
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );

        // A foreground checkpoint on day 9 itself is a no-op after that.
        // FR-17's lock still reads lastReplanDate - the ring has set it to
        // today, so a foreground trigger is a no-op (that the lock itself
        // fires is checked by test/checkpoint_test.dart).
        expect(midnight(appState.lastReplanDate!), _utc(0, 0, day: 9));
      });
    });

    // docs/TODO.md T-71: only the ring checkpoint may treat today as
    // concluded. For FR-17's recovery and a setting change, today has not
    // rung yet - the day must stay in the window (FR-11) and must not be
    // counted (FR-9).
    test('recovery replan (todayAlreadyRang=false): today stays in the window and is not counted',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(9, 0, day: 10), // 09:00, today has NOT rung
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
      );

      // The window starts TODAY, not tomorrow -> today is still revisable.
      expect(appState.pendingDayValues['2026-03-10'], isNotNull);
      // FR-9: today does not count; only the last concluded day (day 9) is
      // counted.
      expect(appState.gapDayCounter, 1);
      expect(appState.lastReplanDate, _utc(0, 0, day: 10));
    });

    test('ring replan (todayAlreadyRang=true): today is fixed, the window starts tomorrow',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(6, 0, day: 10),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );

      expect(appState.pendingDayValues['2026-03-10'], isNull); // not in the window
      expect(appState.pendingDayValues['2026-03-11'], isNotNull);
    });

    test('T-74c: the very first replan reports no missed appointment', () async {
      final appState = await _freshAppState();

      final result = await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 9))],
        todayAlreadyRang: true,
      );

      // With no history, there is no appointment "missed by the last
      // alarm" - previously this was a false report on the very first app
      // start.
      expect(result.possiblyMissedAppointment, isFalse);
    });

    test('FR-15: a ManualAlarm remains completely untouched by replan()',
        () async {
      final appState = await _freshAppState();
      final manualAlarm = ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0));
      appState.manualAlarms.add(manualAlarm);

      await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
      );

      expect(appState.manualAlarms, [manualAlarm]);
      expect(appState.manualAlarms.single.time,
          const TimeOfDay(hour: 3, minute: 0));
    });

    test(
        'FR-15 (the spec bullet itself): a ManualAlarm at 03:00 on a day whose '
        'curve gives 07:00 - the planned value stays exactly 07:00', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      // An enabled manual alarm at 03:00 - it would be "the earliest alarm"
      // of every day if anything here read manual alarms.
      appState.manualAlarms.add(
          ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0), enabled: true));

      await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [],
      );

      for (var d = 10; d <= 16; d++) {
        expect(appState.pendingDayValues[isoDate(_utc(0, 0, day: d))],
            _utc(7, 0, day: d).millisecondsSinceEpoch,
            reason: 'day $d: the manual 03:00 must not enter the plan');
      }
    });
  });

  // The test groups for runAlarmRingCheckpoint, onAppForegroundCheckpoint, and
  // runForegroundCheckpointSafely have moved to test/checkpoint_test.dart -
  // these three entry points were absorbed into runSchedulingCheckpoint()
  // (docs/TODO.md T-87). The assertions themselves are unchanged there, only
  // the call path is unified. That file also explains why checkpoint 1
  // deliberately does NOT reinterpret pendingDayValues: the replan() that
  // follows directly recomputes every still-open day with the fresh offset
  // and applies it via FR-18, which supersedes any reinterpretation.
  // Checkpoint 2 needs it for exactly the opposite reason, because it must
  // not replan (its group below).

  group('window construction (T-74d)', () {
    test('7 distinct days result across the daylight-saving transition',
        () async {
      final appState = await _freshAppState();
      // Local markers across the autumn transition (Europe/Berlin: 2026-10-25).
      // With add(Duration(days:)), two _isoDate keys collided, one day got
      // planned twice, one never.
      await replan(
        appState,
        now: () => DateTime(2026, 10, 23, 6, 0), // local, not UTC
        offsetAt: fixedOffset(const Duration(hours: 2)),
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );

      final planned = appState.pendingDayValues.keys.toSet();
      for (final day in [24, 25, 26, 27, 28, 29, 30]) {
        expect(planned, contains('2026-10-${day.toString().padLeft(2, '0')}'),
            reason: 'day $day is missing from the window');
      }
    });
  });

  group('runTimezoneCheckpoint2 (FR-16 checkpoint 2)', () {
    test(
        'persists the currently read offset directly via SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({'lastCheckedUtcOffsetMinutes': 60});
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        offsetAt: fixedOffset(const Duration(hours: 9)),
        prefs: prefs,
      );

      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 9 * 60);
    });

    // FR-16's actual job (Phase 5 step 22): react to a detected offset
    // change. Only T-61 (Option B) makes this possible correctly - a
    // preferredWakeUpTime-derived value is an instant whose LOCAL digits
    // must be preserved (alarm-clock convention), while a
    // hardFloor-derived one, by contrast, keeps its instant (the appointment
    // doesn't shift). Checkpoint 2 has no calendar access, so it can't
    // derive this itself - hence the persisted marker.
    test('offset change: digit-anchored values keep their local digits, instant-anchored ones keep their instant',
        () async {
      final digitDay = DateTime.utc(2026, 3, 11, 5, 0); // 07:00 local at +2
      final instantDay = DateTime.utc(2026, 3, 12, 4, 0); // real appointment
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 120, // +2
        'pendingDayValues': jsonEncode({
          '2026-03-11': digitDay.millisecondsSinceEpoch,
          '2026-03-12': instantDay.millisecondsSinceEpoch,
        }),
        'pendingDayInstantAnchored': jsonEncode({
          '2026-03-11': false,
          '2026-03-12': true,
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        offsetAt: fixedOffset(const Duration(hours: 9)),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 12, 0),
      );

      final values = (jsonDecode(prefs.getString('pendingDayValues')!)
          as Map<String, dynamic>);
      // 07:00 local stays 07:00 local, now under +9 -> 22:00 UTC the day before.
      expect(values['2026-03-11'],
          DateTime.utc(2026, 3, 10, 22, 0).millisecondsSinceEpoch);
      // The appointment day stays exactly the same instant.
      expect(values['2026-03-12'], instantDay.millisecondsSinceEpoch);
      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 9 * 60);
    });

    test('an unchanged offset -> no value is touched', () async {
      final value = DateTime.utc(2026, 3, 11, 5, 0);
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 120,
        'pendingDayValues':
            jsonEncode({'2026-03-11': value.millisecondsSinceEpoch}),
        'pendingDayInstantAnchored': jsonEncode({'2026-03-11': false}),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        offsetAt: fixedOffset(const Duration(hours: 2)),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 12, 0),
      );

      final values = (jsonDecode(prefs.getString('pendingDayValues')!)
          as Map<String, dynamic>);
      expect(values['2026-03-11'], value.millisecondsSinceEpoch);
    });

    test('already-past (rung) values remain unchanged', () async {
      final past = DateTime.utc(2026, 3, 9, 5, 0);
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 120,
        'pendingDayValues':
            jsonEncode({'2026-03-09': past.millisecondsSinceEpoch}),
        'pendingDayInstantAnchored': jsonEncode({'2026-03-09': false}),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        offsetAt: fixedOffset(const Duration(hours: 9)),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 12, 0),
      );

      final values = (jsonDecode(prefs.getString('pendingDayValues')!)
          as Map<String, dynamic>);
      expect(values['2026-03-09'], past.millisecondsSinceEpoch);
    });

    test(
        'writes the same SharedPreferences key as AppState.lastCheckedUtcOffset (readable safely across the isolate)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        offsetAt: fixedOffset(const Duration(hours: 5)),
        prefs: prefs,
      );

      final appState = AppState();
      await appState.initialized;
      expect(appState.lastCheckedUtcOffset, const Duration(hours: 5));
    });

    // docs/TODO.md T-206: FR-16's new "Test:" bullets, verbatim.
    _t206Checkpoint2Bullets();
  });

  group('T-163: per-event calendar times reach Diag when opted in', () {
    setUp(() {
      Diag.resetForTest();
      Diag.setIncludeClockTimes(true);
    });

    test(
        'every non-all-day event within the window is logged, not just the '
        'earliest', () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [
          _meetingAt(_utc(9, 0, day: 12)),
          _meetingAt(_utc(14, 30, day: 12)),
        ],
      );

      final events =
          Diag.records.where((r) => r.event == DiagEvent.dayEventTime).toList();
      expect(events, hasLength(2),
          reason: 'both events that day must be logged, not only the one '
              'hardFloor picked as earliest');
      final starts =
          events.map((r) => r.fields[DiagField.eventStartMinuteOfDay]).toSet();
      expect(starts, {9 * 60, 14 * 60 + 30});
      final ends =
          events.map((r) => r.fields[DiagField.eventEndMinuteOfDay]).toSet();
      expect(ends, {10 * 60, 15 * 60 + 30});
    });

    test('an all-day event produces no dayEventTime record', () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [
          Meeting(
            from: _utc(0, 0, day: 12),
            to: _utc(0, 0, day: 13),
            isAllDay: true,
            startTimeZone: 'Etc/UTC',
            endTimeZone: 'Etc/UTC',
          ),
        ],
      );

      expect(
          Diag.records.where((r) => r.event == DiagEvent.dayEventTime),
          isEmpty,
          reason: 'an all-day event has no meaningful minute-of-day and '
              'never sets the hard floor - it must not be logged as one');
    });

    test(
        'an ignored event produces no dayEventTime record, even though a '
        "sibling event on the same day does (independent audit's own T-163 "
        'gap: this is the same non-all-day filter the "an all-day event '
        'produces no dayEventTime record" case above already covers, but '
        'for the ignored-event path, which is filtered upstream once - see '
        "replan.dart's own comment right above the Diag.dayEventTime call)",
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      final ignoredEvent = _meetingAt(_utc(9, 0, day: 12), id: 'evt-ignored');
      appState.setEventIgnored(ignoredEvent, true);

      await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [
          ignoredEvent,
          _meetingAt(_utc(14, 30, day: 12), id: 'evt-kept'),
        ],
      );

      final events =
          Diag.records.where((r) => r.event == DiagEvent.dayEventTime).toList();
      expect(events, hasLength(1),
          reason: 'the ignored event must not be logged - only its '
              'non-ignored sibling');
      expect(
          events.single.fields[DiagField.eventStartMinuteOfDay], 14 * 60 + 30,
          reason: 'the one record present must be the kept event, not the '
              'ignored one');
    });

    test('nothing is logged when the switch is off (default)', () async {
      Diag.setIncludeClockTimes(false);
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      await replan(
        appState,
        now: () => ringDay,
        offsetAt: fixedOffset(Duration.zero),
        fetchEvents: (start, end) async => [_meetingAt(_utc(9, 0, day: 12))],
      );

      expect(
          Diag.records.where((r) => r.event == DiagEvent.dayEventTime),
          isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// docs/TODO.md T-206 - FR-16 checkpoint 2 after a daylight-saving change.
// The spec's new "Test:" bullets (daylight saving, stale baseline, torn pair,
// anchored wins, no change, and the location-change bullet's T-206 note),
// verbatim. Zone rules are injected (Europe/Berlin via `package:timezone`),
// never the process zone. Derived cases: test/replan_dst_test.dart.
// ---------------------------------------------------------------------------

int _ms(int month, int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, month, day, hour, minute).millisecondsSinceEpoch;

/// "Plan made Sat 28 Mar 2026 (CET)", as T-206 plans it: Sat 28 Mar has
/// rung at 07:00 CET (06:00 UTC); Sun 29 Mar .. Sat 4 Apr are 07:00 CEST
/// (05:00 UTC), each with its planned clock time 07:00 paired with that
/// value; `lastCheckedUtcOffset` still +1.
Map<String, Object> _plannedAcrossSpringChange({
  Map<String, Object?> clockTimeOverrides = const {},
  Map<String, int?> valueOverrides = const {},
  Map<String, bool> anchoredOverrides = const {},
}) {
  final days = [for (var d = 29; d <= 35; d++) DateTime.utc(2026, 3, d)];
  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  final values = <String, int?>{
    '2026-03-28': _ms(3, 28, 6),
    for (final d in days) iso(d): _ms(d.month, d.day, 5),
    ...valueOverrides,
  };
  final clockTimes = <String, Object?>{
    for (final d in days)
      iso(d): {
        'c': DateTime.utc(d.year, d.month, d.day, 7).millisecondsSinceEpoch,
        'v': _ms(d.month, d.day, 5),
      },
    ...clockTimeOverrides,
  }..removeWhere((_, v) => v == null);
  return {
    'lastCheckedUtcOffsetMinutes': 60,
    'pendingDayValues': jsonEncode(values),
    'pendingDayInstantAnchored': jsonEncode({
      for (final key in values.keys) key: false,
      ...anchoredOverrides,
    }),
    'pendingDayClockTimes': jsonEncode(clockTimes),
  };
}

Map<String, dynamic> _json(SharedPreferences prefs, String key) =>
    jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;

void _t206Checkpoint2Bullets() {
  late tz.Location berlin;
  late ZoneOffsetAt berlinRules;
  setUpAll(() {
    tzdata.initializeTimeZones();
    berlin = tz.getLocation('Europe/Berlin');
    berlinRules = zoneRules(berlin);
  });

  // Checkpoint 2 on Sun 29 Mar 2026 at 03:30 CEST (+2), i.e. 01:30 UTC.
  DateTime sunday0330() => tz.TZDateTime(berlin, 2026, 3, 29, 3, 30);

  test(
      'Test (daylight saving): the zone stays "Europe/Berlin", clocks move '
      'overnight from CET (+1) to CEST (+2) -> the next checkpoint detects the '
      'changed offset. Re-resolving the planned clock times leaves every '
      'planned value unchanged, because they were already planned with the '
      'CEST rules (T-206)', () async {
    SharedPreferences.setMockInitialValues(_plannedAcrossSpringChange());
    final prefs = await SharedPreferences.getInstance();
    final before = _json(prefs, 'pendingDayValues');
    final clockTimesBefore = _json(prefs, 'pendingDayClockTimes');

    await runTimezoneCheckpoint2(
        offsetAt: berlinRules, prefs: prefs, now: sunday0330);

    expect(_json(prefs, 'pendingDayValues'), before);
    expect(_json(prefs, 'pendingDayClockTimes'), clockTimesBefore);
    expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 120);
  });

  test(
      'Test (stale baseline, T-206): plan made Sat 28 Mar 2026 (CET): Sun 29 '
      'Mar = 07:00 CEST = 05:00 UTC, planned clock time 07:00; '
      'lastCheckedUtcOffset still +1; checkpoint 2 at Sun 29 Mar 03:30 CEST '
      '(+2) -> change detected, Sun stays 05:00 UTC (the old shift would give '
      '04:00 UTC = 06:00 CEST), and lastCheckedUtcOffset becomes +2', () async {
    // Requirements T32: the plan is MADE by replan (not seeded), and asserted
    // both after the replan and after checkpoint 2 - the second assertion
    // alone would pass on the pre-T-206 code for the wrong reason (its
    // one-offset plan gives 06:00 UTC, which the old shift "repairs").
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
    appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
    appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
    appState.maxDailyDelta = const Duration(minutes: 30);
    appState.lastProcessedConcludedDay = DateTime(2026, 3, 27);
    appState.pendingDayValues = {
      '2026-03-27': _ms(3, 27, 6),
      '2026-03-28': _ms(3, 28, 6),
    };

    await replan(
      appState,
      now: () => tz.TZDateTime(berlin, 2026, 3, 28, 7, 0),
      offsetAt: berlinRules,
      fetchEvents: (start, end) async => [],
      todayAlreadyRang: true,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(_json(prefs, 'pendingDayValues')['2026-03-29'], _ms(3, 29, 5),
        reason: 'after the replan: Sun 29 Mar is 07:00 CEST = 05:00 UTC');
    final clockTimes = prefs.getString('pendingDayClockTimes');
    expect(clockTimes, isNotNull,
        reason: 'the replan must write pendingDayClockTimes');
    expect((jsonDecode(clockTimes!) as Map<String, dynamic>)['2026-03-29'], {
      'c': DateTime.utc(2026, 3, 29, 7).millisecondsSinceEpoch,
      'v': _ms(3, 29, 5),
    });
    expect(_json(prefs, 'pendingDayInstantAnchored')['2026-03-29'], isFalse);

    await prefs.setInt('lastCheckedUtcOffsetMinutes', 60);
    await runTimezoneCheckpoint2(
        offsetAt: berlinRules, prefs: prefs, now: sunday0330);

    final values = _json(prefs, 'pendingDayValues');
    for (var d = 29; d <= 35; d++) {
      final day = DateTime.utc(2026, 3, d);
      expect(values[day.toIso8601String().substring(0, 10)],
          _ms(day.month, day.day, 5),
          reason: 'after checkpoint 2: $day still 07:00 CEST');
    }
    expect(values['2026-03-28'], _ms(3, 28, 6),
        reason: 'FR-11: the rung Saturday is never touched');
    expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 120);
  });

  test(
      'Test (torn pair, T-206): the same, but the entry\'s paired value '
      'differs from pendingDayValues[Sun] -> Sun is left untouched', () async {
    SharedPreferences.setMockInitialValues(_plannedAcrossSpringChange(
      clockTimeOverrides: {
        '2026-03-29': {
          'c': DateTime.utc(2026, 3, 29, 7).millisecondsSinceEpoch,
          'v': _ms(3, 29, 6),
        },
      },
    ));
    final prefs = await SharedPreferences.getInstance();

    await runTimezoneCheckpoint2(
        offsetAt: berlinRules, prefs: prefs, now: sunday0330);

    expect(_json(prefs, 'pendingDayValues')['2026-03-29'], _ms(3, 29, 5));
    expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 120);
  });

  test(
      'Test (anchored wins, T-206): a day with pendingDayInstantAnchored = '
      'true and a planned clock time -> untouched', () async {
    SharedPreferences.setMockInitialValues(_plannedAcrossSpringChange(
      anchoredOverrides: {'2026-03-29': true},
      // Intact (paired value = the stored value), and re-resolving it would
      // give 06:00 UTC - so leaving it alone is a decision, not a no-op.
      clockTimeOverrides: {
        '2026-03-29': {
          'c': DateTime.utc(2026, 3, 29, 8).millisecondsSinceEpoch,
          'v': _ms(3, 29, 5),
        },
      },
    ));
    final prefs = await SharedPreferences.getInstance();

    await runTimezoneCheckpoint2(
        offsetAt: berlinRules, prefs: prefs, now: sunday0330);

    expect(_json(prefs, 'pendingDayValues')['2026-03-29'], _ms(3, 29, 5));
  });

  test(
      'Test (no change, T-206): the same offset as at the last checkpoint -> '
      'nothing but the offset is written; pendingDayValues and '
      'pendingDayClockTimes are byte-identical afterwards', () async {
    SharedPreferences.setMockInitialValues(
        {..._plannedAcrossSpringChange(), 'lastCheckedUtcOffsetMinutes': 120});
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getString('pendingDayValues');
    final clockTimes = prefs.getString('pendingDayClockTimes');

    await runTimezoneCheckpoint2(
        offsetAt: berlinRules, prefs: prefs, now: sunday0330);

    expect(prefs.getString('pendingDayValues'), values);
    expect(prefs.getString('pendingDayClockTimes'), clockTimes);
    expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 120);
  });

  test(
      'Test (location change), T-206 note: with a planned clock time of 09:00 '
      'stored, R_plan under +9 gives 09:00 in zone B - the same instant as '
      'the legacy shift gives without one', () async {
    // Tomorrow's value: 09:00 in zone A (+1) = 08:00 UTC; 09:00 in zone B
    // (+9) = 00:00 UTC.
    final tomorrow = DateTime.utc(2026, 3, 11, 8, 0).millisecondsSinceEpoch;
    final inZoneB = DateTime.utc(2026, 3, 11, 0, 0).millisecondsSinceEpoch;
    for (final withClockTime in [true, false]) {
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 60,
        'pendingDayValues': jsonEncode({'2026-03-11': tomorrow}),
        'pendingDayInstantAnchored': jsonEncode({'2026-03-11': false}),
        if (withClockTime)
          'pendingDayClockTimes': jsonEncode({
            '2026-03-11': {
              'c': DateTime.utc(2026, 3, 11, 9).millisecondsSinceEpoch,
              'v': tomorrow,
            },
          }),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        offsetAt: fixedOffset(const Duration(hours: 9)),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 13, 0), // 14:00 in zone A
      );

      expect(_json(prefs, 'pendingDayValues')['2026-03-11'], inZoneB,
          reason: withClockTime ? 'R_plan(09:00) under +9' : 'legacy shift');
      if (withClockTime) {
        expect(_json(prefs, 'pendingDayClockTimes')['2026-03-11'],
            {'c': DateTime.utc(2026, 3, 11, 9).millisecondsSinceEpoch,
             'v': inZoneB},
            reason: 'the paired value moves with the value');
      }
      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 9 * 60);
    }
  });
}
