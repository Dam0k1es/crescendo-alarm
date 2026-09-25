import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';

// docs/TODO.md T-141: replan() is where pendingDayValues/disabledDays
// already get pruned to the same "yesterday" retention bound (T-82) -
// scheduledAlarms needs the identical treatment, or it just keeps growing by
// one entry per planned day forever.

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

// Built as DateTime.utc, not the local DateTime(...) constructor: this
// suite's `now`/`deviceUtcOffset: Duration.zero` only ever pretend the
// DOMAIN layer is at UTC+0 - planAlarmSync's own frame-safe `_toMinute`
// still converts a genuinely local DateTime via the real OS timezone
// (`.toUtc()`), which on this dev machine (UTC+0) happened to be a no-op
// but is not on every CI leg. Found via CI's America/St_Johns (UTC-3:30)
// leg: the local constructor shifted this fixture's alarm by 3.5 hours,
// enough to flip it from "already past" to "still ahead", which made
// planAlarmSync's safety-critical "never remove a possibly-ringing alarm"
// check treat it as removable - exactly the frame-confusion bug class
// CLAUDE.md warns about, just in a test fixture rather than production
// code (a real device's own local clock has no such cross-frame mismatch).
ScheduledAlarm _alarmOn(DateTime day, {int id = 1}) => ScheduledAlarm(
      time: DateTime.utc(day.year, day.month, day.day, 7, 30),
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
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
  test('a ScheduledAlarm older than the retention bound is pruned on '
      'replan', () async {
    final appState = await _freshAppState();
    final ringDay = _utc(0, 0, day: 10);
    appState.scheduledAlarms = [
      _alarmOn(DateTime(2026, 3, 1), id: 99), // well over a week stale
    ];

    await replan(
      appState,
      now: () => ringDay,
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async => const [],
    );

    expect(appState.scheduledAlarms.any((a) => a.id == 99), isFalse);
  });

  test("today's ScheduledAlarm survives replan even though its own time is "
      'already in the past by the time replan runs', () async {
    final appState = await _freshAppState();
    // 08:00 "now", alarm at 07:30 - the alarm's own time has already
    // passed, exactly the state it would be in while still actively
    // ringing. planAlarmSync's own removal loop already skips this case for
    // exactly that reason; pruning must agree, not override it.
    final ringDay = _utc(8, 0, day: 10);
    appState.scheduledAlarms = [
      _alarmOn(DateTime(2026, 3, 10), id: 7),
    ];

    await replan(
      appState,
      now: () => ringDay,
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async => const [],
    );

    expect(appState.scheduledAlarms.any((a) => a.id == 7), isTrue,
        reason: "today's alarm could still be ringing - pruning must never "
            'touch it');
  });
}
