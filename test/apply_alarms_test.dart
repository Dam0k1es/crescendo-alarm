import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/apply_alarms.dart';
import 'package:flutter/material.dart' show TimeOfDay;

// docs/TODO.md T-63: replan() computed the week correctly into
// pendingDayValues, but NOTHING ever turned it into a real alarm - the wake
// behaviour still came exclusively from the old Scheduler. This file
// specifies the missing bridge: pendingDayValues -> ScheduledAlarms.
//
// Important for testability: appState.addAlarm() rejects times in the past
// (real DateTime.now(), not injectable) - the applier tests therefore use
// real future times, while the pure planAlarmSync tests use fixed, injected
// "now" values.

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

ScheduledAlarm _alarmAt(DateTime time, {int id = 1, double volume = 0.8}) =>
    ScheduledAlarm(
      time: time,
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      volume: volume,
      id: id,
    );

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  group('planAlarmSync (T-63, rein)', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('nothing planned, nothing present -> no change', () {
      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });

    test('a future planned value with no existing alarm -> one is created', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, [planned]);
      expect(plan.toRemove, isEmpty);
    });

    test('a matching alarm already exists -> no duplicate, no removal', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned)],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });

    test('an existing alarm that is no longer planned -> is removed', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final stale = _alarmAt(DateTime(2026, 3, 11, 9, 0), id: 2);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [stale],
        now: now,
      );

      expect(plan.toAdd, [planned]);
      expect(plan.toRemove, [stale]);
    });

    test('FR-11: an already-past (triggered) planned value is not re-set', () {
      final past = DateTime(2026, 3, 9, 7, 0);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(past): past.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });

    test('a null value (gap day/safety valve) creates no alarm and removes an existing one',
        () {
      final day = DateTime(2026, 3, 11);
      final existing = _alarmAt(DateTime(2026, 3, 11, 7, 30), id: 3);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(day): null},
        existingScheduledAlarms: [existing],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, [existing]);
    });

    // Safety-critical: the ring checkpoint (FR-8) runs WHILE an alarm is
    // ringing - its own time is then in the past. If the sync removed it as
    // "no longer planned", AppState.removeAlarm() would silence it mid-ring
    // via Alarm.stop() and defeat the "guaranteed wake-up".
    test('an existing alarm in the past is NEVER removed (it could be ringing right now)',
        () {
      final ringing = _alarmAt(DateTime(2026, 3, 10, 5, 55), id: 4);

      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: [ringing],
        now: now, // 06:00 - so the alarm just rang
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    // Load-bearing invariant: replan()'s window always begins TOMORROW (the
    // day that just rang is fixed, FR-11), so today's daily value only still
    // sits in pendingDayValues because replan() does NOT prune old entries.
    // Scenario: yesterday, today's 07:00 was planned; today at 03:00 a
    // checkpoint runs (e.g. FR-17 after a reboot). Today's alarm still lies
    // in the future and must be preserved - if pendingDayValues were
    // "cleaned up", this sync would delete it and the user would oversleep.
    test('today\'s not-yet-rung alarm is preserved even though the window only starts tomorrow',
        () {
      final todayValue = DateTime(2026, 3, 10, 7, 0); // planned yesterday for today
      final tomorrowValue = DateTime(2026, 3, 11, 7, 30); // from the new window
      final existingToday = _alarmAt(todayValue, id: 7);

      final plan = planAlarmSync(
        pendingDayValues: {
          _iso(todayValue): todayValue.millisecondsSinceEpoch,
          _iso(tomorrowValue): tomorrowValue.millisecondsSinceEpoch,
        },
        existingScheduledAlarms: [existingToday],
        now: DateTime(2026, 3, 10, 3, 0), // 03:00 today, before the alarm
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, [tomorrowValue]);
    });

    // docs/TODO.md T-74e: AppState and the platform can drift apart (the QR
    // dismiss used to stop ALL stored alarms, without adjusting the AppState
    // lists). Then this sync was a no-op and the user was left without an
    // alarm.
    test('a planned day whose alarm is missing from the platform -> is re-set',
        () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final stale = _alarmAt(planned, id: 9);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [stale],
        now: now,
        platformAlarmIds: const {}, // the platform has nothing left at all
      );

      expect(plan.toRemove, [stale]); // the stale AppState entry goes
      expect(plan.toAdd, [planned]); // and gets freshly set
    });

    test('if the platform matches exactly, the sync stays a no-op', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 9)],
        now: now,
        platformAlarmIds: {9},
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    // docs/TODO.md T-84: the reconciliation only ever compared the minute, so
    // a changed tone/volume/gentle-wake setting only took effect once a day
    // got replanned anyway - for already-armed alarms, possibly never.
    group('T-84: properties belong in the reconciliation', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      test('a differing tone -> the alarm is replaced', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: false,
              tone: 'assets/sounds/alt.mp3',
              id: 11,
            )
          ],
          now: now,
          tone: 'assets/sounds/lollipop.mp3',
        );

        expect(plan.toRemove.single.id, 11);
        expect(plan.toAdd, [planned]);
      });

      test('a differing volume -> the alarm is replaced', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [_alarmAt(planned, id: 12, volume: 0.2)],
          now: now,
          volume: 0.9,
        );

        expect(plan.toRemove.single.id, 12);
        expect(plan.toAdd, [planned]);
      });

      test('a differing gentle-wake -> the alarm is replaced', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: false,
              tone: 'assets/sounds/lollipop.mp3',
              id: 13,
            )
          ],
          now: now,
          gentleWake: true,
        );

        expect(plan.toRemove.single.id, 13);
        expect(plan.toAdd, [planned]);
      });

      // docs/TODO.md T-96: the same lesson as with tone and volume - a
      // setting that `planAlarmSync` doesn't compare never affects
      // already-armed alarms.
      test('a differing gentle-wake duration -> the alarm is replaced', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: true,
              tone: 'assets/sounds/lollipop.mp3',
              volume: 0.8,
              gentleWakeDuration: const Duration(minutes: 1),
              id: 21,
            )
          ],
          now: now,
          gentleWake: true,
          gentleWakeDuration: const Duration(minutes: 10),
        );

        expect(plan.toRemove.single.id, 21);
        expect(plan.toAdd, [planned]);
      });

      test('identical properties -> still a no-op', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [_alarmAt(planned, id: 14, volume: 0.8)],
          now: now,
          tone: 'assets/sounds/lollipop.mp3',
          volume: 0.8,
          gentleWake: false,
        );

        expect(plan.toRemove, isEmpty);
        expect(plan.toAdd, isEmpty);
      });

      // Without properties specified (the previous call path), the
      // comparison stays purely time-based - so no caller can accidentally
      // re-set every alarm just because it doesn't know the properties.
      test('with no properties specified, only the time is compared', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: true,
              tone: 'assets/sounds/irgendwas.mp3',
              id: 15,
            )
          ],
          now: now,
        );

        expect(plan.toRemove, isEmpty);
        expect(plan.toAdd, isEmpty);
      });
    });

    // docs/TODO.md T-88: platformAlarmTimes came from Alarm.getAlarms() and
    // thus also contained ManualAlarm times. A ScheduledAlarm on the same
    // minute was therefore wrongly considered "present on the platform".
    test('T-88: a foreign platform alarm on the same minute covers nothing',
        () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 16)],
        // The platform knows the minute - but not under this
        // ScheduledAlarm's id (e.g. because a ManualAlarm sits there instead).
        platformAlarmIds: const {999},
        now: now,
      );

      expect(plan.toRemove.single.id, 16);
      expect(plan.toAdd, [planned]);
    });

    test('T-88: its own platform entry covers it', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 17)],
        platformAlarmIds: const {17},
        now: now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    test('the comparison is minute-precise (seconds/milliseconds don\'t create a duplicate)', () {
      final planned = DateTime(2026, 3, 11, 7, 30, 45, 123);
      final existing = _alarmAt(DateTime(2026, 3, 11, 7, 30), id: 5);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [existing],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });
  });

  group('applyPlannedAlarms (T-63, against a real AppState)', () {
    test('creates a ScheduledAlarm for a planned future value', () async {
      final appState = await _freshAppState();
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.length, 1);
      expect(appState.scheduledAlarms.single.time.hour, planned.hour);
      expect(appState.scheduledAlarms.single.time.minute, planned.minute);
    });

    test('removes a ScheduledAlarm that is no longer planned', () async {
      final appState = await _freshAppState();
      final obsolete = DateTime.now().add(const Duration(days: 2));
      appState.scheduledAlarms = [_alarmAt(obsolete, id: 42)];
      appState.pendingDayValues = const {};

      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms, isEmpty);
    });

    test('FR-15: ManualAlarms remain completely untouched', () async {
      final appState = await _freshAppState();
      final manualAlarm = ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0));
      appState.manualAlarms.add(manualAlarm);
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      expect(appState.manualAlarms, [manualAlarm]);
      expect(appState.manualAlarms.single.time,
          const TimeOfDay(hour: 3, minute: 0));
    });

    // docs/TODO.md T-84: ScheduledAlarm had no volume field, so every alarm
    // set by FR-18 rang with MyAlarm's default 0.6 and ignored
    // appState.selectedVolume - even though there is a UI for it.
    test('T-84: picks up tone, volume, and gentle-wake from the settings',
        () async {
      final appState = await _freshAppState();
      appState.selectedTone = 'assets/sounds/alt.mp3';
      appState.selectedVolume = 0.35;
      appState.gentleWakeUpEnabled = true;
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      final alarm = appState.scheduledAlarms.single;
      expect(alarm.tone, 'assets/sounds/alt.mp3');
      expect(alarm.volume, 0.35);
      expect(alarm.gentlewake, isTrue);
    });

    test('T-84: a changed volume affects already-planned alarms',
        () async {
      final appState = await _freshAppState();
      appState.selectedVolume = 0.35;
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };
      await applyPlannedAlarms(appState);
      expect(appState.scheduledAlarms.single.volume, 0.35);

      appState.selectedVolume = 0.9;
      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.single.volume, 0.9);
      expect(appState.scheduledAlarms.length, 1);
    });

    test('T-96: picks up the gentle-wake duration from the settings', () async {
      final appState = await _freshAppState();
      appState.gentleWakeUpEnabled = true;
      appState.gentleWakeUpDuration = const Duration(minutes: 7);
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.single.gentleWakeDuration,
          const Duration(minutes: 7));
    });

    test('T-96: a changed duration affects already-planned alarms', () async {
      final appState = await _freshAppState();
      appState.gentleWakeUpEnabled = true;
      appState.gentleWakeUpDuration = const Duration(minutes: 2);
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };
      await applyPlannedAlarms(appState);
      expect(appState.scheduledAlarms.single.gentleWakeDuration,
          const Duration(minutes: 2));

      appState.gentleWakeUpDuration = const Duration(minutes: 12);
      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.single.gentleWakeDuration,
          const Duration(minutes: 12));
      expect(appState.scheduledAlarms.length, 1);
    });

    test('is idempotent: a second call changes nothing', () async {
      final appState = await _freshAppState();
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);
      final afterFirst = List<ScheduledAlarm>.from(appState.scheduledAlarms);
      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.length, afterFirst.length);
      expect(appState.scheduledAlarms.single.id, afterFirst.single.id);
    });
  });

  group('FR-18: two alarms on the same minute (T-116)', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    // FR-18's lead sentence is a postcondition over the SET:
    //
    //   "After every replan, the set of `ScheduledAlarm`s is reconciled to
    //    match exactly the planned values"
    //
    // and FR-18's own test case states the same goal:
    // "a matching alarm already exists -> no duplicate, no removal
    // (idempotent)".
    //
    // The second bullet rule ("an alarm that matches NO planned value is
    // removed"), by contrast, is a condition per alarm, and it doesn't apply
    // to a duplicate under either reading. What governs is the lead
    // sentence: it states the goal, the bullets the means.
    //
    // Independent of any spec reading, the function here also misses its
    // OWN documented contract: "computes what has to change so the set of
    // ScheduledAlarms matches pendingDayValues **exactly**".

    test('one planned value, two matching alarms -> exactly one survives', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [
          _alarmAt(planned, id: 1),
          _alarmAt(planned, id: 2),
        ],
        platformAlarmIds: const {1, 2},
        now: now,
      );

      expect(plan.toRemove.length, 1, reason: 'exactly the duplicate is dropped');
      expect(plan.toAdd, isEmpty, reason: 'the survivor covers the value');
      // The survivor must carry a DIFFERENT id than the removed one:
      // `applyPlannedAlarms` removes by id, and removing the same id would
      // stop the survivor on the platform too.
      expect(plan.toRemove.single.id, isNot(1));
    });

    test('after cleanup, the next run is a fixed point', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 1)],
        platformAlarmIds: const {1},
        now: now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    test('three on the same minute -> two drop out', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [
          _alarmAt(planned, id: 1),
          _alarmAt(planned, id: 2),
          _alarmAt(planned, id: 3),
        ],
        platformAlarmIds: const {1, 2, 3},
        now: now,
      );

      expect(plan.toRemove.length, 2);
      expect(plan.toAdd, isEmpty);
    });

    test('a duplicate in the PAST is never removed', () {
      // FR-18's safety-critical rule remains untouched: "A ScheduledAlarm in
      // the past is NEVER removed (it could be ringing right now; Alarm.stop()
      // would defeat the guaranteed wake-up)."
      final past = DateTime(2026, 3, 10, 5, 55);
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [
          _alarmAt(past, id: 1),
          _alarmAt(past, id: 2),
          _alarmAt(planned, id: 3),
        ],
        platformAlarmIds: const {1, 2, 3},
        now: now,
      );

      expect(plan.toRemove, isEmpty,
          reason: 'both past alarms are left untouched');
      expect(plan.toAdd, isEmpty);
    });

    test('two alarms on DIFFERENT minutes both stay', () {
      // Counter-check against over-correction.
      final a = DateTime(2026, 3, 11, 7, 30);
      final b = DateTime(2026, 3, 12, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {
          _iso(a): a.millisecondsSinceEpoch,
          _iso(b): b.millisecondsSinceEpoch,
        },
        existingScheduledAlarms: [_alarmAt(a, id: 1), _alarmAt(b, id: 2)],
        platformAlarmIds: const {1, 2},
        now: now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });
  });

  group('FR-18: the equality boundary against now (T-123)', () {
    // The most dangerous minute in the whole module, and it was uncovered.
    //
    // FR-18:
    //   "A `ScheduledAlarm` **in the past** is **never** removed: the
    //    application also runs from within FR-8's ring checkpoint, i.e.
    //    *while* an alarm is ringing - and its time is then in the past. To
    //    remove it as 'no longer planned' would silence it mid-ring via
    //    `Alarm.stop()` and defeat the guaranteed wake-up."
    //
    // That is exactly what happens in the CURRENT minute - and the ring
    // checkpoint runs, by definition, within it. The existing test for this
    // works with a five-minute gap; a reformulation of the past check
    // (`isAfter`/`isBefore`, `<=`/`<`, minute instead of second precision)
    // goes unnoticed by it. Proven: such a mutation leaves apply_alarms,
    // replan, replan_audit, checkpoint, app_state, and next_wake_up
    // completely green, and only shows up here.
    //
    // Per FR-18 the comparison is minute-precise, so `now = 07:00:30` falls
    // on minute 07:00.

    final now = DateTime(2026, 3, 10, 7, 0, 30);
    final nowExact = DateTime(2026, 3, 10, 7, 0);

    test('(b) a planned value one minute AFTER now is created', () {
      final value = DateTime(2026, 3, 10, 7, 1);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(value): value.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, [value]);
    });

    test('(c) a planned value one minute BEFORE now is not created', () {
      final value = DateTime(2026, 3, 10, 6, 59);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(value): value.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, isEmpty,
          reason: 'FR-11: already-past planned values are not re-set');
    });

    test('(d) an alarm in the CURRENT minute is never removed', () {
      // The safety-critical line: this alarm is the one currently ringing.
      final ringing = DateTime(2026, 3, 10, 7, 0);
      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: [_alarmAt(ringing, id: 5)],
        now: now,
      );

      expect(plan.toRemove, isEmpty,
          reason: 'Alarm.stop() mid-ring would defeat the guaranteed '
              'wake-up');
    });

    test('(d2) the same when now falls exactly on the alarm minute', () {
      final ringing = DateTime(2026, 3, 10, 7, 0);
      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: [_alarmAt(ringing, id: 5)],
        now: nowExact,
      );

      expect(plan.toRemove, isEmpty);
    });

    test('(e) an unplanned alarm one minute AFTER now is removed', () {
      // Counter-check: the past rule must not turn into a blanket amnesty,
      // or FR-18 would never clean up revised days again.
      final future = DateTime(2026, 3, 10, 7, 1);
      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: [_alarmAt(future, id: 5)],
        now: now,
      );

      expect(plan.toRemove.map((a) => a.id), [5]);
    });

    // (a) A planned value EXACTLY in the current minute with no alarm: FR-18's
    // sentence, taken together, reads as "not after now" -> don't create,
    // and that's how the code behaves. This case is deliberately left
    // without an assertion here: it has no observable effect, because
    // `AppState.addAlarm` rejects a value before `DateTime.now()` anyway
    // (app_state.dart). Both readings end in the same visible result.
  });

  group('FR-18: a platform alarm the app doesn\'t know (T-127)', () {
    // A "ghost alarm" - a platform id with no `ScheduledAlarm` counterpart -
    // is covered by no FR-18 rule: the creation rule concerns planned
    // values, the removal rule `ScheduledAlarm`s. So the sync must not be
    // thrown off by it.
    //
    // Previously uncovered was exactly the combination "its own id AND a
    // foreign one": the existing T-88 case passes a foreign id WITHOUT its
    // own (and then correctly expects removal plus re-creation), the
    // neighboring case exactly its own.

    test('a foreign platform id leaves the sync untouched', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 1)],
        platformAlarmIds: const {1, 4711},
        now: DateTime(2026, 3, 10, 6, 0),
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });
  });
}
