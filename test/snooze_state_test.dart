import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/snooze.dart';

// FR-20 (docs/scheduling-v2-spec.md), docs/TODO.md T-138: state and
// defaults around snooze.

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  group('FR-20: defaults', () {
    test(
        'snooze is on, snoozeTime 5 minutes, durationToWakeUp 00:15 '
        '(maintainer request)', () async {
      final appState = await _fresh();

      expect(appState.snoozeEnabled, isTrue);
      expect(appState.snoozeTime, const Duration(minutes: 5));
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 15));
    });
  });

  group('FR-20: switching on makes the budget usable', () {
    test('at 00:00, durationToWakeUp is armed to 00:10', () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);

      appState.snoozeEnabled = true;

      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 10),
          reason: 'otherwise the budget would be zero and the feature just '
              'switched on would be dead from the start');
    });

    test('an already-set value stays untouched', () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 45);

      appState.snoozeEnabled = true;

      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 45));
    });

    test('switching off does not reset the budget', () async {
      // Counter-check: the user should keep their setting if they only
      // briefly switch snooze off.
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
      appState.snoozeEnabled = true;
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 10));

      appState.snoozeEnabled = false;

      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 10));
    });
  });

  group('FR-20: persistence', () {
    test('snoozeEnabled and snoozeTime survive a restart', () async {
      final first = await _fresh();
      first.snoozeEnabled = true;
      first.snoozeTime = const Duration(minutes: 12);

      final second = AppState();
      await second.initialized;
      expect(second.snoozeEnabled, isTrue);
      expect(second.snoozeTime, const Duration(minutes: 12));
    });

    test('the origin wake call survives a process death', () async {
      // Without it, the user would get the full budget back after a
      // restart - snooze would then be unlimited.
      final first = await _fresh();
      final ring = DateTime(2026, 9, 14, 6, 0);
      first.rememberSnoozeOrigin(4711, ring);

      final second = AppState();
      await second.initialized;
      expect(second.snoozeOriginFor(4711), ring);
    });

    test('a completed wake call is forgotten', () async {
      final appState = await _fresh();
      appState.rememberSnoozeOrigin(4711, DateTime(2026, 9, 14, 6, 0));

      appState.forgetSnoozeOrigin(4711);

      expect(appState.snoozeOriginFor(4711), isNull);
    });
  });

  group('FR-20: the process itself', () {
    late List<({int id, DateTime at, bool gentleWakeAllowed})> armed;
    late List<int> stopped;

    Future<bool> snooze(AppState appState,
        {required int alarmId,
        required DateTime ringTime,
        required DateTime now,
        bool settingFails = false}) {
      armed = [];
      stopped = [];
      return snoozeRingingAlarm(
        appState,
        alarmId: alarmId,
        ringTime: ringTime,
        now: () => now,
        newId: () => 999,
        setAlarm: (id, at, gentleWakeAllowed) async {
          if (settingFails) throw StateError('platform gone');
          armed.add((id: id, at: at, gentleWakeAllowed: gentleWakeAllowed));
        },
        stopAlarm: (id) async => stopped.add(id),
      );
    }

    test('postpones by snoozeTime and ends the old wake call', () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
      appState.snoozeEnabled = true; // sets the budget to 00:10
      final ring = DateTime(2026, 9, 14, 6, 0);

      final ok = await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 0));

      expect(ok, isTrue);
      expect(armed.single.at, DateTime(2026, 9, 14, 6, 5));
      expect(stopped, [1]);
    });

    test('the origin wake call moves along to the new id', () async {
      // Without this, the budget would restart from scratch on every
      // snooze.
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
      appState.snoozeEnabled = true;
      final ring = DateTime(2026, 9, 14, 6, 0);

      await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 0));

      expect(appState.snoozeOriginFor(999), ring);
      expect(appState.snoozeOriginFor(1), isNull);
    });

    test('at the end of the budget nothing is postponed any more - and nothing is stopped',
        () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
      appState.snoozeEnabled = true; // budget 10min
      final ring = DateTime(2026, 9, 14, 6, 0);

      final ok = await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 6));

      expect(ok, isFalse, reason: '06:06 + 5min = 06:11 > 06:10');
      expect(armed, isEmpty);
      expect(stopped, isEmpty,
          reason: 'FR-20: snooze never disables - if it fails, the alarm '
              'keeps ringing');
    });

    test('if arming fails, the old alarm stays armed', () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
      appState.snoozeEnabled = true;

      final ok = await snooze(appState,
          alarmId: 1,
          ringTime: DateTime(2026, 9, 14, 6, 0),
          now: DateTime(2026, 9, 14, 6, 0),
          settingFails: true);

      expect(ok, isFalse);
      expect(stopped, isEmpty,
          reason: 'otherwise the user would be left with no alarm at all');
    });

    test('nothing happens when switched off', () async {
      final appState = await _fresh();
      appState.snoozeEnabled = false; // default on (maintainer request);
      // explicitly off here to test that state.

      final ok = await snooze(appState,
          alarmId: 1,
          ringTime: DateTime(2026, 9, 14, 6, 0),
          now: DateTime(2026, 9, 14, 6, 0));

      expect(ok, isFalse);
      expect(armed, isEmpty);
      expect(stopped, isEmpty);
    });
  });

  // docs/TODO.md T-179 (maintainer request): "die gentle wake up option
  // soll für den finalen alarm im Falle von snooze nicht mehr gelten. der
  // letzte alarm bei nutzung von snooze soll direkt auf der geplanten
  // lautstärke starten." - once postponing again would no longer be
  // allowed, the ring this snooze arms is the FINAL one: no more snoozing
  // is coming, so it must not be softened by a ramp - it needs to be
  // maximally effective right now.
  group('T-179: gentle wake is disabled for the final snoozed ring', () {
    late List<({int id, DateTime at, bool gentleWakeAllowed})> armed;

    Future<bool> snooze(AppState appState,
        {required int alarmId,
        required DateTime ringTime,
        required DateTime now}) {
      armed = [];
      return snoozeRingingAlarm(
        appState,
        alarmId: alarmId,
        ringTime: ringTime,
        now: () => now,
        newId: () => 999,
        setAlarm: (id, at, gentleWakeAllowed) async {
          armed.add((id: id, at: at, gentleWakeAllowed: gentleWakeAllowed));
        },
        stopAlarm: (id) async {},
      );
    }

    test('gentle wake stays allowed while another snooze would still fit',
        () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 30);
      appState.snoozeTime = const Duration(minutes: 5);
      appState.snoozeEnabled = true;
      final ring = DateTime(2026, 9, 14, 6, 0);

      // First press: 06:00 -> 06:05. A further press from 06:05 (-> 06:10)
      // still fits inside the 06:00-06:30 budget, so this is not final yet.
      final ok = await snooze(appState, alarmId: 1, ringTime: ring, now: ring);

      expect(ok, isTrue);
      expect(armed.single.gentleWakeAllowed, isTrue);
    });

    test('gentle wake is disabled once this press exhausts the budget',
        () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 30);
      appState.snoozeTime = const Duration(minutes: 5);
      appState.snoozeEnabled = true;
      final ring = DateTime(2026, 9, 14, 6, 0);

      // Pressed at 06:25 -> new ring at 06:30, exactly the budget's edge.
      // A further press from 06:30 (-> 06:35) would exceed it, so 06:30 is
      // the final ring.
      final ok = await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 25));

      expect(ok, isTrue);
      expect(armed.single.at, DateTime(2026, 9, 14, 6, 30));
      expect(armed.single.gentleWakeAllowed, isFalse);
    });

    test(
        'still allowed one press before the budget is exhausted (boundary '
        'check)', () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 30);
      appState.snoozeTime = const Duration(minutes: 5);
      appState.snoozeEnabled = true;
      final ring = DateTime(2026, 9, 14, 6, 0);

      // Pressed at 06:20 -> new ring at 06:25. A further press from 06:25
      // (-> 06:30) still lands exactly on the budget's edge, which FR-20
      // treats as allowed (inclusive) - so 06:25 is NOT yet the final ring.
      final ok = await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 20));

      expect(ok, isTrue);
      expect(armed.single.at, DateTime(2026, 9, 14, 6, 25));
      expect(armed.single.gentleWakeAllowed, isTrue);
    });
  });
}
