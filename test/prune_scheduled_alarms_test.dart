import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/apply_alarms.dart';
import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-141: planAlarmSync's removal loop deliberately never
// removes a past-dated alarm (it could be ringing right now, and
// Alarm.stop() on it would defeat the guaranteed wake-up) - so nothing else
// ever shrinks AppState.scheduledAlarms, and it grows by one entry per
// planned day forever. Seen live: seven alarms in the Scheduled tab, six of
// them for days already over.
//
// pruneScheduledAlarms is the separate, bounded cleanup this needs - kept
// deliberately apart from planAlarmSync's own safety-critical removal logic,
// with the same retention bound replan() already uses for
// pendingDayValues/disabledDays (docs/TODO.md T-82): "yesterday" is the
// oldest kept day, so a recovery checkpoint whose lastConcludedDay IS
// yesterday still has it to read.

ScheduledAlarm _alarmOn(DateTime day, {int id = 1}) => ScheduledAlarm(
      time: DateTime(day.year, day.month, day.day, 7, 30),
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

void main() {
  final today = DateTime(2026, 3, 10);
  final yesterday = today.subtract(const Duration(days: 1));
  final oldestKeptDay =
      '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-'
      '${yesterday.day.toString().padLeft(2, '0')}';

  test('an alarm older than the retention bound is pruned', () {
    final old = _alarmOn(today.subtract(const Duration(days: 3)), id: 1);

    final result = pruneScheduledAlarms([old], oldestKeptDay: oldestKeptDay);

    expect(result, isEmpty);
  });

  test("today's alarm is never pruned, even though it is 'in the past' by "
      'the time this runs', () {
    // The case that matters most: a naive "remove everything before now"
    // fix would delete an alarm that could still be actively ringing.
    final todayAlarm = _alarmOn(today, id: 2);

    final result =
        pruneScheduledAlarms([todayAlarm], oldestKeptDay: oldestKeptDay);

    expect(result, [todayAlarm]);
  });

  test('yesterday - the retention bound itself - is kept, the day before it '
      'is not', () {
    final yesterdayAlarm = _alarmOn(yesterday, id: 3);
    final dayBeforeAlarm =
        _alarmOn(yesterday.subtract(const Duration(days: 1)), id: 4);

    final result = pruneScheduledAlarms(
      [yesterdayAlarm, dayBeforeAlarm],
      oldestKeptDay: oldestKeptDay,
    );

    expect(result, [yesterdayAlarm]);
  });

  test('a future alarm is always kept', () {
    final future = _alarmOn(today.add(const Duration(days: 5)), id: 5);

    final result =
        pruneScheduledAlarms([future], oldestKeptDay: oldestKeptDay);

    expect(result, [future]);
  });

  test('mixed list: only the stale ones are dropped, order otherwise '
      'preserved', () {
    final stale1 = _alarmOn(today.subtract(const Duration(days: 10)), id: 1);
    final kept1 = _alarmOn(yesterday, id: 2);
    final stale2 = _alarmOn(today.subtract(const Duration(days: 4)), id: 3);
    final kept2 = _alarmOn(today, id: 4);

    final result = pruneScheduledAlarms(
      [stale1, kept1, stale2, kept2],
      oldestKeptDay: oldestKeptDay,
    );

    expect(result, [kept1, kept2]);
  });
}
