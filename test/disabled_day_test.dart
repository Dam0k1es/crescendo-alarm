import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/apply_alarms.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// FR-21 (docs/scheduling-v2-spec.md), docs/TODO.md T-03: a switched-off
// planned alarm does not ring. The cases come from the requirement's
// "Test:" bullets.

DateTime _utc(int h, int m, {int day = 10}) => DateTime.utc(2026, 3, day, h, m);

ScheduledAlarm _alarmAt(DateTime time, {int id = 1}) => ScheduledAlarm(
      time: time,
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      volume: 0.8,
      id: id,
    );

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  group('FR-21: the plan does not arm a switched-off day', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('a switched-off day is not armed', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        disabledDays: {isoDate(planned)},
        now: now,
      );

      expect(plan.toAdd, isEmpty,
          reason: 'the user said "do not wake me" for this day');
    });

    test('an already-armed alarm for this day is removed', () {
      // The "immediately" assurance at the level that enforces it.
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 5)],
        platformAlarmIds: const {5},
        disabledDays: {isoDate(planned)},
        now: now,
      );

      expect(plan.toRemove.map((a) => a.id), [5]);
      expect(plan.toAdd, isEmpty);
    });

    test('other days stay untouched', () {
      // Counter-check against overcorrection.
      final off = DateTime(2026, 3, 11, 7, 30);
      final on = DateTime(2026, 3, 12, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {
          isoDate(off): off.millisecondsSinceEpoch,
          isoDate(on): on.millisecondsSinceEpoch,
        },
        existingScheduledAlarms: const [],
        disabledDays: {isoDate(off)},
        now: now,
      );

      expect(plan.toAdd, [on]);
    });

    test('nothing changes without any switched-off days', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        disabledDays: const {},
        now: now,
      );

      expect(plan.toAdd, [planned]);
    });
  });

  group('FR-21: permanent and across restarts', () {
    test('the next planning run does not arm it again', () async {
      // The assurance that a bare Alarm.stop() fails on: FR-18 rebuilds
      // the alarm set on EVERY re-plan.
      final appState = await _fresh();
      final ringDay = _utc(0, 0, day: 10);
      final tomorrow = dayMarker(ringDay, 1);

      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      appState.setDayEnabled(isoDate(tomorrow), false);

      await replan(
        appState,
        now: () => _utc(6, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => <Meeting>[],
        todayAlreadyRang: true,
      );

      expect(
        appState.scheduledAlarms.where((a) => isoDate(a.time) == isoDate(tomorrow)),
        isEmpty,
        reason: 'FR-21: the next planning run must not repeat it',
      );
      expect(appState.pendingDayValues[isoDate(tomorrow)], isNotNull,
          reason: 'the planned value stays - switched off is not deleted');
    });

    test('the state survives a restart', () async {
      final first = await _fresh();
      first.setDayEnabled('2026-03-11', false);

      final second = AppState();
      await second.initialized;
      expect(second.isDayDisabled('2026-03-11'), isTrue);
    });

    test('switched back on, the planned value applies again immediately', () async {
      final appState = await _fresh();
      appState.setDayEnabled('2026-03-11', false);
      appState.setDayEnabled('2026-03-11', true);

      expect(appState.isDayDisabled('2026-03-11'), isFalse);

      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        disabledDays: appState.disabledDays,
        now: DateTime(2026, 3, 10, 6, 0),
      );
      expect(plan.toAdd, [planned]);
    });
  });
}
