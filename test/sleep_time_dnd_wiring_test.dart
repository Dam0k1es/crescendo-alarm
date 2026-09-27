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

// docs/TODO.md T-198 (R2): "der Mechanismus knüpft an die Benachrichtigung
// zur Schlafenszeit ... Die Zeitplanung ist bzgl des Starts daher zu
// übernehmen." The window is re-armed at exactly the places the bedtime
// reminder is rescheduled - the end of every scheduling checkpoint (after the
// replan, in its `finally`) and every handled alarm - computed from the same
// freshly planned values.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart' as sleep_time_dnd;

class _SilentNotifications implements Notifications {
  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async =>
      id ?? 1;

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

class _Push {
  _Push(this.enabled, this.window, this.plannedAtPushTime);
  final bool enabled;
  final sleep_time_dnd.SleepTimeWindow? window;
  final Map<String, int?> plannedAtPushTime;
}

void main() {
  final pushes = <_Push>[];
  AppState? observed;

  setUp(() {
    pushes.clear();
    observed = null;
    sleep_time_dnd.pushSleepTimeWindow =
        ({required bool enabled, required sleep_time_dnd.SleepTimeWindow? window}) async {
      pushes.add(_Push(enabled, window,
          Map<String, int?>.of(observed?.pendingDayValues ?? const {})));
      return const sleep_time_dnd.SleepTimeDndReport(
          decision: sleep_time_dnd.SleepTimeDndDecision.scheduled);
    };
  });

  tearDown(() {
    sleep_time_dnd.pushSleepTimeWindow =
        sleep_time_dnd.defaultPushSleepTimeWindow;
  });

  Future<AppState> freshAppState() async {
    SharedPreferences.setMockInitialValues({'sleepTimeDndEnabled': true});
    final appState = AppState();
    await appState.initialized;
    await Future<void>.delayed(Duration.zero);
    appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
    appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
    observed = appState;
    pushes.clear();
    return appState;
  }

  test(
      'a scheduling checkpoint re-arms the window after the replan, from the '
      'freshly planned values', () async {
    final appState = await freshAppState();
    // FR-4 plans a value for every appointment-free window day at the
    // preferred wake-up time - enough to give the replan something new.
    appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
    appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
    final now = DateTime.now();
    expect(appState.pendingDayValues, isEmpty,
        reason: 'premise: nothing planned before the checkpoint');

    await runSchedulingCheckpoint(
      appState,
      trigger: CheckpointTrigger.settingsChanged,
      now: () => now,
      fetchEvents: (DateTime start, DateTime end) async => <Meeting>[],
      notifications: _SilentNotifications(),
    );

    expect(pushes, isNotEmpty);
    final last = pushes.last;
    expect(last.enabled, isTrue);
    expect(last.plannedAtPushTime, isNotEmpty,
        reason: 'the final push must see the replan\'s result, not the '
            'state from before it');
    expect(last.window, isNotNull);
    expect(last.plannedAtPushTime.values,
        contains(last.window!.end.millisecondsSinceEpoch),
        reason: 'the window ends at one of the freshly planned wake-ups');
    expect(last.window!.end.difference(last.window!.start),
        const Duration(hours: 8));
  });

  test('the window is re-armed even when the replan itself fails (same '
      '`finally` as the reminder)', () async {
    final appState = await freshAppState();

    await runCheckpointSafely(
      appState,
      trigger: CheckpointTrigger.settingsChanged,
      fetchEvents: (DateTime start, DateTime end) async =>
          throw StateError('calendar plugin down'),
      notifications: _SilentNotifications(),
    );

    expect(pushes, isNotEmpty);
    expect(pushes.last.enabled, isTrue);
  });

  test('a handled alarm re-arms the window (the reminder\'s second call site, '
      'the only one a ManualAlarm dismiss reaches - T-73)', () async {
    final appState = await freshAppState();
    appState.manualAlarms.add(ManualAlarm(
        time: const TimeOfDay(hour: 6, minute: 0), enabled: false, id: 5));

    Handler.onAlarmHandled(appState, 5, notifications: _SilentNotifications());
    await Future<void>.delayed(Duration.zero);

    expect(pushes, hasLength(1));
    expect(pushes.single.enabled, isTrue);
  });
}
