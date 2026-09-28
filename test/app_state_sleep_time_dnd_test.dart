// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

// docs/TODO.md T-198 (R3, R6): the Sleep Habits Do Not Disturb trigger -
// default off, its own NEW preference key (a v1.3.0 install may still hold
// `doNotDisturbEnabled=true` from the removed T-184 feature, which must not
// silently switch this default-off feature on), and what AppState hands the
// native side on every change.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart' as sleep_time_dnd;

class _Push {
  _Push(this.enabled, this.window);
  final bool enabled;
  final sleep_time_dnd.SleepTimeWindow? window;
}

void main() {
  final pushes = <_Push>[];
  var nextReport = const sleep_time_dnd.SleepTimeDndReport(
      decision: sleep_time_dnd.SleepTimeDndDecision.scheduled);

  setUp(() {
    pushes.clear();
    nextReport = const sleep_time_dnd.SleepTimeDndReport(
        decision: sleep_time_dnd.SleepTimeDndDecision.scheduled);
    sleep_time_dnd.pushSleepTimeWindow =
        ({required bool enabled, required sleep_time_dnd.SleepTimeWindow? window}) async {
      pushes.add(_Push(enabled, window));
      return nextReport;
    };
  });

  tearDown(() {
    sleep_time_dnd.pushSleepTimeWindow =
        sleep_time_dnd.defaultPushSleepTimeWindow;
  });

  Future<AppState> freshAppState([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final appState = AppState();
    await appState.initialized;
    // Let the unawaited startup push land before a test starts counting.
    await Future<void>.delayed(Duration.zero);
    pushes.clear();
    return appState;
  }

  group('setting', () {
    test('defaults to off (R6)', () async {
      final appState = await freshAppState();
      expect(appState.sleepTimeDndEnabled, isFalse);
    });

    test('persists under its own new key and notifies listeners', () async {
      final appState = await freshAppState();
      var notified = 0;
      appState.addListener(() => notified++);

      appState.sleepTimeDndEnabled = true;

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sleepTimeDndEnabled'), isTrue);
      expect(notified, greaterThan(0));
    });

    test(
        'a stale v1.3.0 doNotDisturbEnabled=true does NOT switch the feature '
        'on, and the removed feature\'s keys are cleared on load', () async {
      final appState = await freshAppState({
        'doNotDisturbEnabled': true,
        'doNotDisturbPreviousFilter': 4,
        'doNotDisturbActivatedAt': 1,
        'doNotDisturbTargetWakeUp': 2,
      });

      expect(appState.sleepTimeDndEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      for (final key in const [
        'doNotDisturbEnabled',
        'doNotDisturbPreviousFilter',
        'doNotDisturbActivatedAt',
        'doNotDisturbTargetWakeUp',
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    });
  });

  group('what reaches the native side', () {
    test('cold start pushes the current state once, so a window survives a '
        'force-stop or an app update without waiting for a checkpoint',
        () async {
      SharedPreferences.setMockInitialValues({'sleepTimeDndEnabled': true});
      final appState = AppState();
      await appState.initialized;
      await Future<void>.delayed(Duration.zero);

      expect(pushes, hasLength(1));
      expect(pushes.single.enabled, isTrue);
    });

    test('switching it on pushes enabled with the window for the next alarm',
        () async {
      final appState = await freshAppState();
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      appState.manualAlarms.add(ManualAlarm(
          time: const TimeOfDay(hour: 6, minute: 0), id: 1));

      appState.sleepTimeDndEnabled = true;
      await Future<void>.delayed(Duration.zero);

      expect(pushes, hasLength(1));
      expect(pushes.single.enabled, isTrue);
      final window = pushes.single.window!;
      expect(window.end.difference(window.start), const Duration(hours: 8));
      expect(window.end.hour, 6);
      expect(window.end.minute, 0);
    });

    test('switching it off pushes disabled with no window (R6: the native '
        'side then leaves Do Not Disturb if it had switched it on)', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      appState.manualAlarms.add(ManualAlarm(
          time: const TimeOfDay(hour: 6, minute: 0), id: 1));

      appState.sleepTimeDndEnabled = false;
      await Future<void>.delayed(Duration.zero);

      expect(pushes, hasLength(1));
      expect(pushes.single.enabled, isFalse);
      expect(pushes.single.window, isNull);
    });

    test('R3: the same window is armed whether or not the bedtime reminder '
        'notification itself is enabled', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      final now = DateTime(2026, 3, 10, 14, 0);
      appState.manualAlarms.add(ManualAlarm(
          time: const TimeOfDay(hour: 6, minute: 0), id: 1));

      appState.reminderEnabled = false;
      await appState.refreshSleepTimeDnd(now: () => now);
      appState.reminderEnabled = true;
      await appState.refreshSleepTimeDnd(now: () => now);

      expect(pushes, hasLength(2));
      expect(pushes[0].enabled, isTrue);
      expect(pushes[0].window, isNotNull);
      expect(pushes[1].window!.start, pushes[0].window!.start);
      expect(pushes[1].window!.end, pushes[0].window!.end);
    });

    test('enabled but no alarm at all -> enabled, no window', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});

      await appState.refreshSleepTimeDnd();

      expect(pushes.single.enabled, isTrue);
      expect(pushes.single.window, isNull);
    });

    test('an excluded manual alarm does not define the window', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      final now = DateTime(2026, 3, 10, 14, 0);
      appState.manualAlarms.add(ManualAlarm(
          time: const TimeOfDay(hour: 3, minute: 0),
          excludeFromSleepTime: true,
          id: 1));
      appState.manualAlarms.add(ManualAlarm(
          time: const TimeOfDay(hour: 7, minute: 0), id: 2));

      await appState.refreshSleepTimeDnd(now: () => now);

      expect(pushes.single.window!.end,
          DateTime(2026, 3, 11, 7, 0));
    });
  });

  group('the FR-21 on/off switch (independent review of 201b740, A2)', () {
    // applyManualAlarmEnabled flips `alarm.enabled` only AFTER the platform
    // call, and the push inside _setAlarm/_stopAlarm computed the window
    // before that - switching the target alarm off left its window armed.
    test('switching the target alarm off re-arms the window for the next one',
        () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      final target = ManualAlarm(time: const TimeOfDay(hour: 6, minute: 0), id: 1);
      final later = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 30), id: 2);
      appState.manualAlarms
        ..add(target)
        ..add(later);

      // Pinned "now" (docs/TODO.md T-201): on the real clock this case
      // depended on the local time of day the suite happened to run at.
      final applied = await appState.setManualAlarmEnabled(target, false,
          now: () => DateTime(2026, 9, 28, 2, 0),
          armAlarm: (alarm, at) async {}, stopAlarm: (id) async {});
      await Future<void>.delayed(Duration.zero);

      expect(applied, isTrue);
      expect(pushes, isNotEmpty);
      final window = pushes.last.window!;
      expect(window.end.hour, 7);
      expect(window.end.minute, 30);
    });

    test('switching an earlier alarm on makes it the window\'s end', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      final earlier = ManualAlarm(
          time: const TimeOfDay(hour: 5, minute: 0), enabled: false, id: 1);
      final later = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 30), id: 2);
      appState.manualAlarms
        ..add(earlier)
        ..add(later);

      // docs/TODO.md T-201: pinned before 05:00. On the real clock this
      // failed whenever the suite ran between 05:00 and 07:30 LOCAL time -
      // then the next 05:00 is tomorrow and 07:30 today correctly wins (CI's
      // Pacific/Chatham leg, which hit that window on 2026-09-27).
      await appState.setManualAlarmEnabled(earlier, true,
          now: () => DateTime(2026, 9, 28, 2, 0),
          armAlarm: (alarm, at) async {}, stopAlarm: (id) async {});
      await Future<void>.delayed(Duration.zero);

      expect(pushes.last.window!.end.hour, 5);
    });

    test('...but between 05:00 and 07:30 the later alarm today comes first '
        '(docs/TODO.md T-201 counter-test)', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      final earlier = ManualAlarm(
          time: const TimeOfDay(hour: 5, minute: 0), enabled: false, id: 1);
      final later = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 30), id: 2);
      appState.manualAlarms
        ..add(earlier)
        ..add(later);

      await appState.setManualAlarmEnabled(earlier, true,
          now: () => DateTime(2026, 9, 28, 6, 0),
          armAlarm: (alarm, at) async {}, stopAlarm: (id) async {});
      await Future<void>.delayed(Duration.zero);

      final end = pushes.last.window!.end.toLocal();
      expect((end.day, end.hour, end.minute), (28, 7, 30));
    });
  });

  group('pushes when the feature is off', () {
    test(
        'off and already delivered as off: arm/cancel-driven refreshes do not '
        'reach the channel again (the default for every user)', () async {
      final appState = await freshAppState();
      // The cold-start push (off) was delivered - see freshAppState.

      await appState.refreshSleepTimeDnd();
      await appState.refreshSleepTimeDnd();

      expect(pushes, isEmpty);
    });

    test('an undelivered "off" is retried on the next refresh', () async {
      nextReport = sleep_time_dnd.SleepTimeDndReport.notDelivered;
      final appState = await freshAppState();
      nextReport = const sleep_time_dnd.SleepTimeDndReport(
          decision: sleep_time_dnd.SleepTimeDndDecision.disabled);

      await appState.refreshSleepTimeDnd();

      expect(pushes, hasLength(1));
      expect(pushes.single.enabled, isFalse);
    });
  });

  group('v1.3.0 leftover (independent review of 201b740, B3)', () {
    test('the removed feature\'s keys on load trigger a one-time cleanup of '
        'its old Do Not Disturb mode', () async {
      var cleanups = 0;
      sleep_time_dnd.clearLegacyDoNotDisturb = () async => cleanups++;
      addTearDown(() => sleep_time_dnd.clearLegacyDoNotDisturb =
          sleep_time_dnd.defaultClearLegacyDoNotDisturb);

      await freshAppState({'doNotDisturbEnabled': true});
      expect(cleanups, 1);

      // Keys are gone after that load, so a second start does not repeat it.
      final reloaded = AppState(
          getPrefsInstance: () async => SharedPreferences.getInstance());
      await reloaded.initialized;
      expect(cleanups, 1);
    });

    test('no removed keys -> no cleanup call', () async {
      var cleanups = 0;
      sleep_time_dnd.clearLegacyDoNotDisturb = () async => cleanups++;
      addTearDown(() => sleep_time_dnd.clearLegacyDoNotDisturb =
          sleep_time_dnd.defaultClearLegacyDoNotDisturb);

      await freshAppState();
      expect(cleanups, 0);
    });
  });

  group('diagnostics (no clock values, no strings)', () {
    test('a sync is logged with the native decision and what fired', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      Diag.resetForTest();
      nextReport = const sleep_time_dnd.SleepTimeDndReport(
        decision: sleep_time_dnd.SleepTimeDndDecision.alreadyActive,
        startFired: true,
        endFired: false,
        applyFailed: false,
        accessMissing: false,
      );

      await appState.refreshSleepTimeDnd();

      final logged =
          Diag.records.where((r) => r.event == DiagEvent.sleepTimeDnd).toList();
      expect(logged, hasLength(1));
      expect(logged.single.fields[DiagField.dndDecision],
          DiagDndDecision.alreadyActive.code);
      expect(logged.single.fields[DiagField.dndStartFired], 1);
      expect(logged.single.fields[DiagField.dndEndFired], 0);
    });

    test('an unchanged, uneventful decision is not logged again', () async {
      final appState = await freshAppState({'sleepTimeDndEnabled': true});
      Diag.resetForTest();
      // Different from what the startup push already returned (scheduled),
      // so the first of the three below is a genuine change.
      nextReport = const sleep_time_dnd.SleepTimeDndReport(
          decision: sleep_time_dnd.SleepTimeDndDecision.catchUp);

      await appState.refreshSleepTimeDnd();
      await appState.refreshSleepTimeDnd();
      await appState.refreshSleepTimeDnd();

      expect(
          Diag.records.where((r) => r.event == DiagEvent.sleepTimeDnd),
          hasLength(1),
          reason: 'one replan arms and cancels several alarms, and each of '
              'those syncs - repeating the same decision would push real '
              'history out of the 512-entry ring');
    });
  });
}
