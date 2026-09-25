import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// Regressions from the independent spec review (2026-09-11), at the
// replan()/state-bookkeeping level. The domain-layer counterparts live in
// test/scheduling_v2_audit_test.dart.
//
// Each case names the id under which it is tracked in docs/TODO.md.

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
  group('FR-11: the rung day value is fixed, even later the same day (T-106)',
      () {
    // FR-11:
    //
    //   "A value already computed for a day, but not yet triggered, stays
    //    revisable [...] Only the value that has actually been triggered is
    //    fixed forever."
    //
    // "Forever" includes the rest of that same day. Only the ring checkpoint
    // sets `todayAlreadyRang`; for every other trigger the window therefore
    // starts at TODAY again, and the merge used to overwrite the
    // already-rung value without protection.
    //
    // FR-17's daily lock catches `appForeground` - there the ring has
    // already set `lastReplanDate` to today. `settingsChanged` and
    // `manualSync` are deliberately not subject to it and carry the case
    // alone: the tone and volume controls, the four duration pickers, the
    // preferredWakeUpTime toggle, the gentle-wake toggle and the sync
    // button.

    test('a non-ring replan the same day leaves the rung value standing',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      final rangAt = _utc(6, 0, day: 10);

      // Backstory: 09:00 yesterday, rang today at 06:00 (an appointment at
      // 06:00 had forced the value).
      appState.pendingDayValues = {
        isoDate(dayMarker(ringDay, -1)): _utc(9, 0, day: 9).millisecondsSinceEpoch,
        isoDate(ringDay): rangAt.millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = ringDay;
      appState.lastReplanDate = ringDay;
      appState.preferredWakeUpTime = const TimeOfDay(hour: 9, minute: 0);

      // 08:00: the appointment is cancelled, the user changes a setting.
      await replan(
        appState,
        now: () => _utc(8, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        // settingsChanged/manualSync: today does NOT count as concluded
        todayAlreadyRang: false,
      );

      expect(
        appState.pendingDayValues[isoDate(ringDay)],
        rangAt.millisecondsSinceEpoch,
        reason: 'FR-11: the triggered value is fixed, even for the rest of the day',
      );
    });

    test('the following day, however, stays entirely revisable', () async {
      // Counter-check against over-correction: FR-11's first half
      // ("not yet triggered -> revisable") must be preserved.
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      final nextDay = dayMarker(ringDay, 1);

      appState.pendingDayValues = {
        isoDate(ringDay): _utc(6, 0, day: 10).millisecondsSinceEpoch,
        isoDate(nextDay): _utc(6, 0, day: 11).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = ringDay;
      appState.lastReplanDate = ringDay;
      appState.preferredWakeUpTime = const TimeOfDay(hour: 9, minute: 0);
      appState.maxDailyDelta = const Duration(minutes: 30);

      await replan(
        appState,
        now: () => _utc(8, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: false,
      );

      // Previously this only checked `isNot(06:00)` - "anything else". That
      // was too weak: the spec-correct value of 06:30 satisfies it, but so
      // did the 09:00 this used to produce, and the test stayed green even
      // though `maxDailyDelta` was exceeded sixfold (T-114).
      expect(
        appState.pendingDayValues[isoDate(nextDay)],
        _utc(6, 30, day: 11).millisecondsSinceEpoch,
        reason: 'FR-3/FR-4: the anchor is the rung 06:00 value from Mar 10, '
            'maxDailyDelta = 30min -> exactly one step',
      );
    });

    test('the ring checkpoint itself keeps writing today\'s value', () async {
      // Second counter-check: the lock must only apply to already-concluded
      // days, not to the ring that concludes them in the first place.
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      appState.pendingDayValues = {
        isoDate(dayMarker(ringDay, -1)): _utc(7, 0, day: 9).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = dayMarker(ringDay, -1);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 11))],
        todayAlreadyRang: true,
      );

      expect(appState.pendingDayValues[isoDate(dayMarker(ringDay, 1))], isNotNull,
          reason: 'the ring path\'s window starts tomorrow and gets written');
    });
  });

  group('FR-3: the anchor is the most recently concluded day, not "yesterday" (T-114)',
      () {
    // FR-3, verbatim:
    //
    //   "`lastEffectiveWakeTime` is deliberately NOT its own field: it is
    //    always the entry in `pendingDayValues` for the most recently
    //    concluded day, and as a second source could only drift apart from
    //    it."
    //
    // Which day that is lives in `lastProcessedConcludedDay` - exactly the
    // field T-75 separated from `lastReplanDate` for this purpose.
    // `replan()`, however, used to read the anchor from a day derived from
    // the TRIGGER: "yesterday" for everything except the ring. If today has
    // already rung, though, the most recently concluded day is TODAY.
    //
    // T-106 already protected the rung value from being overwritten - the
    // same run then still ignored it as the anchor regardless. That is
    // exactly the "second source" FR-3 warns against.

    test('an anchor exists, but the wrong one: the step stays within maxDailyDelta',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      appState.pendingDayValues = {
        isoDate(dayMarker(ringDay, -1)):
            _utc(6, 0, day: 9).millisecondsSinceEpoch,
        isoDate(ringDay): _utc(6, 0, day: 10).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = ringDay; // today has rung
      appState.lastReplanDate = ringDay;
      appState.maxDailyDelta = const Duration(minutes: 60);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 9, minute: 0);

      await replan(
        appState,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: false, // settingsChanged
      );

      expect(
        appState.pendingDayValues[isoDate(dayMarker(ringDay, 1))],
        _utc(7, 0, day: 11).millisecondsSinceEpoch,
        reason: 'a step of 60min from the rung 06:00',
      );
    });

    test('the anchor is missing for yesterday: no jump onto preferredWakeUpTime',
        () async {
      // The harder case. If the entry for yesterday is missing - the normal
      // state after the T-82 prune, or after a gap - the anchor comes back
      // `null` and `computeWeekPlan` takes FR-10's cold start, which jumps
      // straight to preferredWakeUpTime with no `maxDailyDelta` bound at
      // all. The entry for today, however, is there.
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      appState.pendingDayValues = {
        isoDate(ringDay): _utc(6, 0, day: 10).millisecondsSinceEpoch,
        isoDate(dayMarker(ringDay, 1)):
            _utc(6, 0, day: 11).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = ringDay;
      appState.lastReplanDate = ringDay;
      appState.maxDailyDelta = const Duration(minutes: 30);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 9, minute: 0);

      await replan(
        appState,
        now: () => _utc(8, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: false,
      );

      expect(
        appState.pendingDayValues[isoDate(dayMarker(ringDay, 1))],
        _utc(6, 30, day: 11).millisecondsSinceEpoch,
        reason: 'FR-10\'s cold start does not apply here at all - a '
            'lastEffectiveWakeTime exists, it is stored under TODAY',
      );
    });

    test('a progress marker in the future does not stall the planning',
        () async {
      // Counterpart to T-109 one level down: the marker is a device-local
      // date with no clamping and can, through a backward clock correction
      // (or a zone change across the date boundary), lie BEFORE today's
      // date. A day in the future must never count as "already concluded" -
      // otherwise the whole window counts as concluded and nothing at all
      // gets planned anymore.
      final appState = await _freshAppState();
      final today = _utc(0, 0, day: 10);

      appState.pendingDayValues = {
        isoDate(dayMarker(today, -1)):
            _utc(6, 0, day: 9).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = dayMarker(today, 7);
      appState.maxDailyDelta = const Duration(minutes: 30);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 6, minute: 0);

      await replan(
        appState,
        now: () => _utc(8, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: false,
      );

      expect(appState.pendingDayValues[isoDate(dayMarker(today, 1))], isNotNull,
          reason: 'the week must still be planned regardless');
    });
  });

  group('FR-18: replan() actually applies the plan (T-117)', () {
    // The most serious single finding of the 2026-09-11 review, and it's not
    // about behaviour, but about coverage: the seam between "plan computed"
    // and "alarm registered" was uncovered across the ENTIRE suite.
    //
    // `apply_alarms_test.dart` checks `planAlarmSync` purely and
    // `applyPlannedAlarms` directly - but nothing checks that `replan()`
    // calls them at all. Remove the call, and nine test files stay green
    // (replan, apply_alarms, checkpoint, replan_audit, checkpoint_audit,
    // handler_replan_wiring, handler_on_alarm_handled, next_wake_up,
    // app_state_scheduling_v2). The binding existed only as a comment.
    //
    // And it's not a hypothetical regression: this is exactly how the
    // scheduling-v2 implementation was once already entirely without effect
    // - the week was computed correctly and never turned into an alarm
    // (T-63). The comment at the call site names it; from now on a test
    // does too.
    //
    // Deliberately with REAL future times: `AppState.addAlarm` compares
    // against `DateTime.now()` and doesn't accept a past instant in the
    // first place - an injected past "now" would prove nothing here.

    Set<DateTime> minutesOf(Iterable<DateTime> times) =>
        times.map((t) => DateTime(t.year, t.month, t.day, t.hour, t.minute)).toSet();

    // FR-18, verbatim: "For every planned value **after now** with no
    // matching alarm, exactly one is created." Today's window day, depending
    // on the time of the test run, may already lie behind us - it then
    // correctly does NOT belong in the alarm set, and FR-18 says exactly
    // that.
    Set<DateTime> plannedFutureMinutes(AppState appState, DateTime now) =>
        minutesOf(appState.pendingDayValues.values
            .whereType<int>()
            .map(DateTime.fromMillisecondsSinceEpoch)
            .where((t) => t.isAfter(now)));

    test('the planned values become registered alarms', () async {
      final appState = await _freshAppState();
      final now = DateTime.now();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => now,
        deviceUtcOffset: now.timeZoneOffset,
        fetchEvents: (start, end) async => [],
      );

      expect(appState.pendingDayValues.values.whereType<int>(), isNotEmpty,
          reason: 'precondition: something was actually planned');
      expect(appState.scheduledAlarms, isNotEmpty,
          reason: 'FR-18: every planned value after now becomes an alarm');

      expect(minutesOf(appState.scheduledAlarms.map((a) => a.time)),
          plannedFutureMinutes(appState, now),
          reason: 'the alarm set matches exactly the planned values '
              'after now');
    });

    test('a changed plan pulls the registered alarms along', () async {
      // FR-16's decidable half: "no full recomputation of the
      // segments/runs - that only follows at the NEXT regular planning
      // run." That the next such run pulls the already-registered alarms
      // along is thereby guaranteed - and was likewise uncovered.
      final appState = await _freshAppState();
      final now = DateTime.now();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => now,
        deviceUtcOffset: now.timeZoneOffset,
        fetchEvents: (start, end) async => [],
      );
      final before = minutesOf(appState.scheduledAlarms.map((a) => a.time));
      expect(before, isNotEmpty);

      appState.preferredWakeUpTime = const TimeOfDay(hour: 9, minute: 30);
      await replan(
        appState,
        now: () => now,
        deviceUtcOffset: now.timeZoneOffset,
        fetchEvents: (start, end) async => [],
      );

      final after = minutesOf(appState.scheduledAlarms.map((a) => a.time));
      expect(after, isNot(before),
          reason: 'the next planning run pulls the alarms along');

      expect(after, plannedFutureMinutes(appState, now));
    });
  });

  group('The same ring checkpoint twice yields the same state (T-128)', () {
    // Idempotence at the checkpoint level. For exactly this bug class - a
    // run that touches state a second time even though it already processed
    // it - there was no safety net until now, and it has already struck six
    // times in this project (T-67, T-71, T-77, T-80, T-106, T-114).

    test('the second ring does not count the same day again', () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      appState.pendingDayValues = {
        isoDate(dayMarker(ringDay, -1)):
            _utc(7, 0, day: 9).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = dayMarker(ringDay, -6);
      appState.gapDayCounter = 0;
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );
      final counterAfterFirst = appState.gapDayCounter;
      final valuesAfterFirst = Map<String, int?>.from(appState.pendingDayValues);
      final markerAfterFirst = appState.lastProcessedConcludedDay;

      await replan(
        appState,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );

      expect(appState.gapDayCounter, counterAfterFirst,
          reason: 'FR-9: every concluded day is counted EXACTLY ONCE');
      expect(appState.pendingDayValues, valuesAfterFirst);
      expect(appState.lastProcessedConcludedDay, markerAfterFirst);
    });
  });
}
