import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm_enable.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/direct_boot_mirror.dart'
    as direct_boot_mirror;
import 'package:crescendo_alarm/utils/notifications.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-217 follow-up: step 2 of the one checkpoint sequence
// (`runSchedulingCheckpoint` -> `_reconcileWithPlatform`).
//
// What a real Android 15+ force-stop does (review N1): it cancels the
// AlarmManager entries, but the `alarm` plugin's own storage - which
// `Alarm.getAlarms()` reads - survives, and the relaunch's `Alarm.init`
// re-arms every future entry and stops every past one
// (`FakeAlarmPlatform.forceStopAndRelaunch`). So nothing future is lost;
// what IS lost is a manual alarm whose time passed while the app was
// stopped: the plugin drops it, and the list kept showing it switched on
// with nothing registered (the long-idle test of 2026-10-04/05). Manual
// alarms have no FR-18; this step re-arms them at their next occurrence.
//
// The scheduled half is a cheap safety net: every app open already runs a
// `manualSync` checkpoint whose replan applies FR-18 (main.dart,
// `_syncCalendarAndAlarmsOnOpen`) - but only if the calendar read succeeds.
// Re-applying the EXISTING plan needs no calendar read and is not a replan;
// it runs only if a future enabled scheduled alarm is missing (for example
// because the plugin's own re-arm of it failed).

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

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

ManualAlarm _manual(int id, int hour, {bool enabled = true}) => ManualAlarm(
      time: TimeOfDay(hour: hour, minute: 0),
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

typedef _Fetch = Future<List<Meeting>> Function(DateTime start, DateTime end);

Future<void> _launch(AppState appState, DateTime now, {_Fetch? fetchEvents}) =>
    runCheckpointSafely(
      appState,
      trigger: CheckpointTrigger.manualSync,
      now: () => now,
      fetchEvents: fetchEvents ?? (from, to) async => [],
      notifications: _SilentNotifications(),
    );

Future<List<Meeting>> _events(DateTime from, DateTime to) async => [
      for (var d = DateTime(from.year, from.month, from.day);
          d.isBefore(to);
          d = DateTime(d.year, d.month, d.day + 1))
        Meeting(
          from: DateTime(d.year, d.month, d.day, 9),
          to: DateTime(d.year, d.month, d.day, 10),
          isAllDay: false,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        ),
    ];

Future<List<Meeting>> _calendarDown(DateTime from, DateTime to) async =>
    throw StateError('calendar unavailable');

/// Arms [alarm] through the app's own path, as of [at].
Future<void> _armAt(AppState appState, ManualAlarm alarm, DateTime at) =>
    appState.setManualAlarmEnabled(alarm, true, now: () => at);

/// Counts platform reads - the applier's own `Alarm.getAlarms()` is how a
/// test sees whether FR-18 ran.
class _ReadCounter {
  _ReadCounter(AppState appState) {
    final inner = appState.debugPlatformGetAll!;
    appState.debugPlatformGetAll = () {
      reads++;
      return inner();
    };
  }
  int reads = 0;
}

void main() {
  final friday = DateTime(2026, 10, 2, 18, 0);
  final sundayEvening = DateTime(2026, 10, 4, 19, 0);

  tearDown(() {
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {};
  });

  group('manual alarms: the one the plugin dropped while stopped', () {
    test('the long-idle sequence: armed Friday for Saturday 07:00, '
        'force-stopped, opened Sunday evening -> re-armed once for Monday '
        '07:00; a still-registered one is not re-set, a disabled one never '
        'armed', () async {
      final appState = await _freshAppState();
      final platform = FakeAlarmPlatform()..attach(appState);
      final missed = _manual(11, 7);
      final pending = _manual(12, 21);
      final off = _manual(13, 8, enabled: false);
      appState.manualAlarms.addAll([missed, pending, off]);
      await _armAt(appState, missed, friday);
      await _armAt(appState, pending, DateTime(2026, 10, 4, 18, 0));
      platform.setIds.clear();

      platform.forceStopAndRelaunch(sundayEvening);
      expect(platform.armed.keys, [12],
          reason: 'the plugin dropped the past entry, kept the future one');

      await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

      expect(platform.setIds, [11]);
      expect(
          platform.armed[11]!.dateTime.isAtSameMomentAs(nextManualOccurrence(
              missed.time as TimeOfDay, sundayEvening, missed.repeatOnDays)),
          isTrue);
      expect(platform.armed[11]!.dateTime.toLocal(),
          DateTime(2026, 10, 5, 7, 0));
    });

    test('an alarm ringing right now is never re-armed, even if absent from '
        'the store', () async {
      final appState = await _freshAppState();
      final platform = FakeAlarmPlatform()..attach(appState);
      appState.manualAlarms.add(_manual(11, 7));
      platform.ringing.add(11);

      await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

      expect(platform.setIds, isNot(contains(11)));
    });

    test('platform state unknown: nothing is armed blindly', () async {
      final appState = await _freshAppState();
      final platform = FakeAlarmPlatform()..attach(appState);
      appState.debugPlatformGetAll = () async => throw StateError('no channel');
      appState.manualAlarms.add(_manual(11, 7));

      await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

      expect(platform.setIds, isEmpty);
    });
  });

  group('scheduled alarms: safety net on the existing plan', () {
    Future<(AppState, FakeAlarmPlatform)> plannedFriday() async {
      final appState = await _freshAppState();
      final platform = FakeAlarmPlatform()..attach(appState);
      await _launch(appState, friday, fetchEvents: _events);
      expect(platform.armed, isNotEmpty);
      platform.setIds.clear();
      platform.stopIds.clear();
      return (appState, platform);
    }

    Set<int> futureEnabledIds(AppState appState, DateTime now) =>
        appState.scheduledAlarms
            .where((a) => a.enabled && (a.time as DateTime).isAfter(now))
            .map((a) => a.id)
            .toSet();

    test('a future entry the plugin failed to re-arm is restored exactly '
        'once even when the calendar read fails (the replan cannot run '
        'FR-18 then)', () async {
      final (appState, platform) = await plannedFriday();
      platform.forceStopAndRelaunch(sundayEvening);
      platform.armed.remove(futureEnabledIds(appState, sundayEvening).first);

      await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

      final expected = futureEnabledIds(appState, sundayEvening);
      expect(platform.armed.keys.toSet(), expected);
      expect(platform.setIds.length, 1,
          reason: 'only the lost day is armed again, exactly once');
      expect(expected, contains(platform.setIds.single));
    });

    test('nothing future missing: the applier does not run (no churn)',
        () async {
      final (appState, platform) = await plannedFriday();
      platform.forceStopAndRelaunch(sundayEvening);
      final counter = _ReadCounter(appState);

      await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

      expect(counter.reads, 2,
          reason: 'one read for the manual half, one for the scheduled '
              'check - a third would be the applier');
      expect(platform.setIds, isEmpty);
      expect(platform.stopIds, isEmpty);
    });

    test('review N3: a past, unregistered ScheduledAlarm (it stays listed '
        'after ringing) does not re-run the applier on every checkpoint',
        () async {
      final (appState, platform) = await plannedFriday();
      final past = appState.scheduledAlarms
          .where((a) => a.enabled)
          .reduce((a, b) =>
              (a.time as DateTime).isBefore(b.time as DateTime) ? a : b);
      final now = (past.time as DateTime).add(const Duration(hours: 2));
      platform.forceStopAndRelaunch(now);
      expect(platform.armed.containsKey(past.id), isFalse);
      expect(appState.scheduledAlarms, contains(past));
      final counter = _ReadCounter(appState);

      await _launch(appState, now, fetchEvents: _calendarDown);

      expect(counter.reads, 2);
    });

    test('platform unreadable: nothing is done', () async {
      final (appState, platform) = await plannedFriday();
      platform.armed.clear();
      appState.debugPlatformGetAll = () async => throw StateError('no channel');

      await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

      expect(platform.setIds, isEmpty);
      expect(platform.stopIds, isEmpty);
    });

    test('a ringing (past-dated) scheduled alarm is left untouched', () async {
      final (appState, platform) = await plannedFriday();
      final ringing = appState.scheduledAlarms
          .where((a) => a.enabled)
          .reduce((a, b) =>
              (a.time as DateTime).isBefore(b.time as DateTime) ? a : b);
      final now = (ringing.time as DateTime).add(const Duration(minutes: 1));
      platform.ringing.add(ringing.id);
      platform.forceStopAndRelaunch(now);
      platform.armed.remove(futureEnabledIds(appState, now).first);

      await _launch(appState, now, fetchEvents: _calendarDown);

      expect(platform.stopIds, isNot(contains(ringing.id)));
      expect(platform.setIds, isNot(contains(ringing.id)));
      expect(platform.armed.keys.toSet(),
          {ringing.id, ...futureEnabledIds(appState, now)});
    });
  });

  test('review N4: every checkpoint re-mirrors the direct-boot due time, so '
      'a ring stopped without an FR-18 diff does not leave the rung time '
      'mirrored (a false "Alarm missed" after the next reboot)', () async {
    final appState = await _freshAppState();
    final platform = FakeAlarmPlatform()..attach(appState);
    final alarm = _manual(11, 7);
    appState.manualAlarms.add(alarm);
    await _armAt(appState, alarm, sundayEvening);
    final mirrored = <DateTime?>[];
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {
      mirrored.add(dueAt);
    };
    platform.setIds.clear();

    await _launch(appState, sundayEvening, fetchEvents: _calendarDown);

    expect(platform.setIds, isEmpty,
        reason: 'nothing was re-armed, so no arm path refreshed the mirror');
    expect(mirrored, isNotEmpty);
    expect(mirrored.last!.toLocal(), DateTime(2026, 10, 5, 7, 0));
  });
}
