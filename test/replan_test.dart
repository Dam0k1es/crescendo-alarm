import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

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

Meeting _meetingAt(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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

    test(
        'a multi-day gap (e.g. a reboot): gapDayCounter is advanced individually for each skipped day',
        () async {
      final appState = await _freshAppState();

      await replan(
        appState,
        now: () => _utc(0, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );
      expect(appState.gapDayCounter, 1); // day 9 itself: no appointment.

      // A 3-day gap (day 10, 11, 12 never processed individually) - all 3
      // with no appointment.
      await replan(
        appState,
        now: () => _utc(0, 0, day: 12),
        deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
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
            deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
        );
        expect(appState.gapDayCounter, 1,
            reason: 'the recovery itself must not count today (FR-9)');

        // Day 10, 07:00: the real alarm rings. NOW day 10 is concluded and
        // must be counted.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.pendingDayValues['2026-03-10'],
            _utc(7, 0, day: 10).millisecondsSinceEpoch);

        // Recovery at 03:00 on day 10, calendar still empty.
        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
        );

        // Day 10 rings at 07:00, and only now is the 05:00 appointment
        // known - so the alarm missed it.
        final result = await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          deviceUtcOffset: Duration.zero,
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
          deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
      );

      expect(appState.manualAlarms, [manualAlarm]);
      expect(appState.manualAlarms.single.time,
          const TimeOfDay(hour: 3, minute: 0));
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
        deviceUtcOffset: const Duration(hours: 2),
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
        readOffset: () => const Duration(hours: 9),
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
        readOffset: () => const Duration(hours: 9),
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
        readOffset: () => const Duration(hours: 2),
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
        readOffset: () => const Duration(hours: 9),
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
        readOffset: () => const Duration(hours: 5),
        prefs: prefs,
      );

      final appState = AppState();
      await appState.initialized;
      expect(appState.lastCheckedUtcOffset, const Duration(hours: 5));
    });
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
        deviceUtcOffset: Duration.zero,
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
        deviceUtcOffset: Duration.zero,
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

    test('nothing is logged when the switch is off (default)', () async {
      Diag.setIncludeClockTimes(false);
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      await replan(
        appState,
        now: () => ringDay,
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(9, 0, day: 12))],
      );

      expect(
          Diag.records.where((r) => r.event == DiagEvent.dayEventTime),
          isEmpty);
    });
  });
}
