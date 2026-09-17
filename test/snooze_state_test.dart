import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/snooze.dart';

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
    test('snooze is off, snoozeTime 5 minutes, durationToWakeUp 00:00',
        () async {
      final appState = await _fresh();

      expect(appState.snoozeEnabled, isFalse);
      expect(appState.snoozeTime, const Duration(minutes: 5));
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 0),
          reason: 'FR-20 sets the default to 00:00 - without snooze there '
              'is no reason to wake up early');
    });
  });

  group('FR-20: switching on makes the budget usable', () {
    test('at 00:00, durationToWakeUp is armed to 00:10', () async {
      final appState = await _fresh();
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 0));

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
    late List<({int id, DateTime at})> armed;
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
        setAlarm: (id, at) async {
          if (settingFails) throw StateError('platform gone');
          armed.add((id: id, at: at));
        },
        stopAlarm: (id) async => stopped.add(id),
      );
    }

    test('postpones by snoozeTime and ends the old wake call', () async {
      final appState = await _fresh();
      appState.snoozeEnabled = true; // setzt das Budget auf 00:10
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
      final appState = await _fresh(); // snoozeEnabled is off

      final ok = await snooze(appState,
          alarmId: 1,
          ringTime: DateTime(2026, 9, 14, 6, 0),
          now: DateTime(2026, 9, 14, 6, 0));

      expect(ok, isFalse);
      expect(armed, isEmpty);
      expect(stopped, isEmpty);
    });
  });
}
