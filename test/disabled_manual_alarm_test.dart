import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/manual_alarm_enable.dart';
import 'package:wakeywakey/models/scheduling/next_wake_up.dart';

// FR-21 (docs/scheduling-v2-spec.md), "Manual alarms" — docs/TODO.md T-03.
//
// The planned half of FR-21 shipped first (test/disabled_day_test.dart); this
// is the other half. A manual alarm is an object the user owns directly, so
// there is no `disabledDays` analogue here — the flag on the object already is
// the durable statement, and the whole defect was that nobody ever acted on it.
//
// The cases below are the "Test:" bullets of FR-21's manual-alarm section.

ManualAlarm _alarmAt(TimeOfDay time, {int id = 7, bool enabled = true}) =>
    ManualAlarm(
      time: time,
      title: 'Wake up',
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      volume: 0.8,
      id: id,
    );

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FR-21: switching a manual alarm off reaches the platform', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('off stops the platform alarm and arms nothing', () async {
      final alarm = _alarmAt(const TimeOfDay(hour: 7, minute: 30));
      final stopped = <int>[];
      final armed = <DateTime>[];

      final ok = await applyManualAlarmEnabled(
        alarm: alarm,
        enabled: false,
        now: now,
        armAlarm: (a, at) async => armed.add(at),
        stopAlarm: (id) async => stopped.add(id),
      );

      expect(ok, isTrue);
      expect(stopped, [7], reason: 'the alarm carrying this id must be cancelled');
      expect(armed, isEmpty, reason: 'switching off never arms anything');
      expect(alarm.enabled, isFalse);
    });

    test('on arms the next occurrence and stops nothing', () async {
      final alarm =
          _alarmAt(const TimeOfDay(hour: 7, minute: 30), enabled: false);
      final stopped = <int>[];
      final armed = <DateTime>[];

      final ok = await applyManualAlarmEnabled(
        alarm: alarm,
        enabled: true,
        now: now,
        armAlarm: (a, at) async => armed.add(at),
        stopAlarm: (id) async => stopped.add(id),
      );

      expect(ok, isTrue);
      expect(armed, [DateTime(2026, 3, 10, 7, 30)],
          reason: '07:30 is still ahead of 06:00, so it is today');
      expect(stopped, isEmpty);
      expect(alarm.enabled, isTrue);
    });

    test('on, with the time already past today, arms tomorrow', () async {
      // The same resolution a freshly created alarm gets (AppState's
      // _getAlarmTime). Switching off and on again must not silently move the
      // alarm to a different day than creating it anew would.
      final alarm =
          _alarmAt(const TimeOfDay(hour: 5, minute: 0), enabled: false);
      final armed = <DateTime>[];

      await applyManualAlarmEnabled(
        alarm: alarm,
        enabled: true,
        now: now,
        armAlarm: (a, at) async => armed.add(at),
        stopAlarm: (id) async {},
      );

      expect(armed, [DateTime(2026, 3, 11, 5, 0)]);
    });

    test('a failed platform call leaves the flag describing reality', () async {
      // Counter-test against a fix that only flips a boolean: if the platform
      // refuses to cancel the alarm, it WILL ring, and the switch must not
      // claim otherwise.
      final alarm = _alarmAt(const TimeOfDay(hour: 7, minute: 30));

      final ok = await applyManualAlarmEnabled(
        alarm: alarm,
        enabled: false,
        now: now,
        armAlarm: (a, at) async {},
        stopAlarm: (id) async => throw StateError('platform unavailable'),
      );

      expect(ok, isFalse);
      expect(alarm.enabled, isTrue,
          reason: 'the alarm is still armed, so the flag must still say so');
    });
  });

  group('FR-21: the state survives a restart', () {
    test('switching off is persisted', () async {
      final appState = await _fresh();
      // Created SWITCHED ON, deliberately: if it were added switched off,
      // `addAlarm` would already have written `enabled: false`, and this test
      // would stay green even with the save in `setManualAlarmEnabled`
      // removed. It only pins the toggle's own write when the stored value has
      // to change (verified by exactly that mutation).
      //
      // Arming throws here - a unit test has no platform channel - and that
      // happens after the alarm was added to the list and saved, so catching
      // it leaves the same state a real device would have.
      try {
        await appState.addAlarm(_alarmAt(const TimeOfDay(hour: 7, minute: 30)));
      } catch (_) {
        // expected: Alarm.set has no channel here
      }
      final stored = appState.manualAlarms.single;
      expect(stored.enabled, isTrue);

      final ok = await appState.setManualAlarmEnabled(stored, false);
      expect(ok, isTrue);

      // docs/TODO.md T-04: a fresh AppState alone does not prove a round-trip.
      // SharedPreferences.getInstance() memoises its instance and answers from
      // an in-process cache, so a "restart" can read back the object graph the
      // test just wrote in memory. Dropping the memoised instance and
      // reloading is what the integration test needed; here it costs nothing
      // and keeps both sides of the assertion honest.
      SharedPreferences.resetStatic();
      await (await SharedPreferences.getInstance()).reload();

      final reloaded = AppState();
      await reloaded.initialized;
      expect(reloaded.manualAlarms.single.enabled, isFalse,
          reason: 'FR-21 assurance 3: across restarts');
    });

    test('a switched-off alarm is not armed when it is added or edited',
        () async {
      // The back door: the user edits the title of a switched-off alarm and it
      // is live again. Oracle for "no arming was attempted": this test
      // environment has no platform channel, so any real Alarm.set throws
      // AlarmException - an attempt would surface here as a failure.
      final appState = await _fresh();

      final result = await appState.addAlarm(
          _alarmAt(const TimeOfDay(hour: 7, minute: 30), enabled: false));

      expect(result['success'], isTrue);
      expect(appState.manualAlarms.single.enabled, isFalse);
    });
  });

  group('FR-21: the bedtime reminder skips what will not ring', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('a switched-off manual alarm does not feed nextWakeUpTime', () {
      final result = nextWakeUpTime(
        pendingDayValues: const <String, int?>{},
        manualAlarms: [
          _alarmAt(const TimeOfDay(hour: 7, minute: 0), id: 1, enabled: false),
          _alarmAt(const TimeOfDay(hour: 9, minute: 0), id: 2),
        ],
        now: now,
      );

      expect(result, DateTime(2026, 3, 10, 9, 0),
          reason: 'a reminder computed from an alarm that will not ring sends '
              'the user to bed for a wake-up that never comes');
    });

    test('a switched-on manual alarm still feeds it', () {
      // Counter-test against over-correction: the reminder must not lose the
      // manual source altogether.
      final result = nextWakeUpTime(
        pendingDayValues: const <String, int?>{},
        manualAlarms: [_alarmAt(const TimeOfDay(hour: 7, minute: 0))],
        now: now,
      );

      expect(result, DateTime(2026, 3, 10, 7, 0));
    });

    test('with every manual alarm switched off, only the plan remains', () {
      final planned = DateTime(2026, 3, 11, 8, 0);
      final result = nextWakeUpTime(
        pendingDayValues: {'2026-03-11': planned.millisecondsSinceEpoch},
        manualAlarms: [
          _alarmAt(const TimeOfDay(hour: 7, minute: 0), enabled: false),
        ],
        now: now,
      );

      expect(result, planned);
    });
  });
}
