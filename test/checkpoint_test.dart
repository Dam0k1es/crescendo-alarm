import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/notifications.dart';

// docs/TODO.md T-77 + T-80 + T-87: runSchedulingCheckpoint() is the one entry
// point for every trigger (ring, app foreground, setting change). Previously
// there were five entry points that differed in four orthogonal dimensions
// (record the offset? treat today as concluded? report? reschedule the
// reminder? swallow errors?) - exactly this matrix produced T-67, T-71, and
// T-80, the same bug three times in the same structure.
//
// The two properties this file guards:
//  * T-77: the sequence is serialized. Four triggers, three of them
//    fire-and-forget - and FR-17's daily lock couldn't protect them, because
//    it reads `lastReplanDate`, which is only written at the END of
//    replan(). If an alarm rings, Android brings the app forward via a
//    full-screen intent -> a second checkpoint while the first is still
//    hanging in calendar I/O.
//  * T-80: the sequence is complete. scheduleSleepReminder() used to run
//    only from initState, the reminder switch, and onAlarmHandled - not
//    from the checkpoints themselves. So on the resume path a replan
//    happened while the bedtime notification (FR-16 checkpoint 2's hook)
//    stayed stuck on the old time.

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

class _RecordingNotifications implements Notifications {
  _RecordingNotifications({this.observe});

  /// Runs on every scheduleNotification call - this makes it possible to
  /// check what state AppState was in at the moment of notification.
  final void Function()? observe;

  final List<DateTime?> scheduledDates = [];
  final List<int?> ids = [];
  int callCount = 0;
  int cancelAllCount = 0;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    callCount++;
    scheduledDates.add(scheduledDate);
    ids.add(id);
    observe?.call();
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async => cancelAllCount++;

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

void main() {
  group('T-77: serialization', () {
    test(
        'two simultaneous foreground checkpoints only advance the day once',
        () async {
      final appState = await _freshAppState();
      // History: day 7 is the last processed day. The checkpoint runs as
      // recovery on day 9, so today does not count as concluded (T-71) -
      // exactly one day (day 8) needs processing.
      appState.lastProcessedConcludedDay = _utc(0, 0, day: 7);
      appState.lastReplanDate = _utc(0, 0, day: 7);

      // The first checkpoint hangs in calendar I/O until we release it -
      // exactly the window in which the second trigger comes in.
      final gate = Completer<void>();
      var fetchCount = 0;
      Future<List<Meeting>> slowFetch(DateTime start, DateTime end) async {
        fetchCount++;
        await gate.future;
        return const [];
      }

      final first = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: slowFetch,
        notifications: _RecordingNotifications(),
      );
      // Give the first call time to run into the fetch.
      await Future<void>.delayed(Duration.zero);
      final second = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: slowFetch,
        notifications: _RecordingNotifications(),
      );

      gate.complete();
      final results = await Future.wait([first, second]);

      expect(fetchCount, 1,
          reason: 'the second trigger must not run into the calendar in '
              'parallel, got $fetchCount calls');
      expect(results.where((r) => r != null).length, 1,
          reason: 'exactly one of the two actually replans');
      expect(appState.gapDayCounter, 1,
          reason: 'exactly day 8 is concluded and appointment-free');
      expect(appState.lastProcessedConcludedDay, _utc(0, 0, day: 8));
    });

    test('a setting change waits for a running ring checkpoint',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      final gate = Completer<void>();
      final order = <String>[];

      final ring = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async {
          order.add('ring-fetch');
          await gate.future;
          return const [];
        },
        notifications: _RecordingNotifications(),
      );
      await Future<void>.delayed(Duration.zero);

      final settings = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(8, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async {
          order.add('settings-fetch');
          return const [];
        },
        notifications: _RecordingNotifications(),
      );

      gate.complete();
      await Future.wait([ring, settings]);

      expect(order, ['ring-fetch', 'settings-fetch'],
          reason: 'strictly one after another, not interleaved');
      // A setting change is NOT subject to FR-17's daily lock - so it must
      // genuinely replan despite the ring on the same day.
      expect(order.contains('settings-fetch'), isTrue);
    });

    test('an error in the first checkpoint does not block the next',
        () async {
      final appState = await _freshAppState();

      await expectLater(
        runSchedulingCheckpoint(
          appState,
          trigger: CheckpointTrigger.alarmRing,
          now: () => _utc(7, 0, day: 9),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => throw StateError('calendar broken'),
          notifications: _RecordingNotifications(),
        ),
        throwsA(isA<StateError>()),
      );

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(result, isNotNull);
    });
  });

  group('T-80: complete sequence', () {
    test('the ring checkpoint replans the bedtime notification', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      final notifications = _RecordingNotifications();

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(notifications.callCount, 1);
      expect(notifications.scheduledDates.single, isNotNull);
      expect(notifications.cancelAllCount, 0,
          reason: 'never cancel globally (T-74b)');
    });

    test('the foreground checkpoint replans it too', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      final notifications = _RecordingNotifications();

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(3, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(notifications.callCount, 1);
    });

    test('the bedtime is determined AFTER the plan, not before', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      var pendingCountAtNotification = -1;
      final notifications = _RecordingNotifications(
        observe: () =>
            pendingCountAtNotification = appState.pendingDayValues.length,
      );

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(pendingCountAtNotification, 7,
          reason: 'the reminder is derived from the fresh plan');
    });

    test(
        'FR-17\'s daily lock also prevents rebuilding the reminder twice on the foreground trigger',
        () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 9);
      appState.lastProcessedConcludedDay = _utc(0, 0, day: 9);
      final notifications = _RecordingNotifications();

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(9, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(result, isNull, reason: 'FR-17: already planned today -> no-op');
      expect(notifications.callCount, 0,
          reason: 'without a replan there is nothing new to schedule either');
    });
  });

  // Ported from the entry points that no longer exist (runAlarmRingCheckpoint,
  // onAppForegroundCheckpoint, runForegroundCheckpointSafely,
  // onSchedulingSettingsChanged) - the assertions remain, only the call path
  // is now unified.
  group('FR-16 checkpoint 1 (ring)', () {
    test('a detected offset change is persisted', () async {
      final appState = await _freshAppState();
      appState.lastCheckedUtcOffset = const Duration(hours: 1);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: const Duration(hours: 9),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(appState.lastCheckedUtcOffset, const Duration(hours: 9));
    });

    test('the ring also always replans (T-61: instant, not digits)',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      appState.lastCheckedUtcOffset = const Duration(hours: 1);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: const Duration(hours: 9),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      // windowStart = day 11; a cold start with preferredWakeUpTime sets day
      // 11 to 07:00 **local**. At deviceUtcOffset = +9 that's the instant
      // 22:00 UTC the day before - exactly the T-61 fix (a real instant is
      // stored, preferredWakeUpTime is a device-local time of day).
      expect(appState.pendingDayValues['2026-03-11'],
          DateTime.utc(2026, 3, 10, 22, 0).millisecondsSinceEpoch);
      expect(appState.lastReplanDate, _utc(0, 0, day: 10));
    });

    test('an unchanged offset leaves the already-rung value untouched',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      appState.lastCheckedUtcOffset = const Duration(hours: 1);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 9),
        deviceUtcOffset: const Duration(hours: 1),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );
      final fixedValue = appState.pendingDayValues['2026-03-10'];

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: const Duration(hours: 1),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(appState.pendingDayValues['2026-03-10'], fixedValue);
      expect(appState.lastCheckedUtcOffset, const Duration(hours: 1));
    });
  });

  group('FR-17 (app foreground)', () {
    test('last planned yesterday -> triggers exactly one checkpoint', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 8);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(result, isNotNull);
      expect(appState.lastReplanDate, _utc(0, 0, day: 10));
    });

    test('already planned today -> no calendar access at all', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 10);
      final pendingBefore = Map.of(appState.pendingDayValues);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async =>
            throw StateError('fetchEvents must not be called'),
        notifications: _RecordingNotifications(),
      );

      expect(result, isNull);
      expect(appState.pendingDayValues, pendingBefore);
    });

    test('regression: a second app start right after the first does not fire',
        () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 8);

      final first = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );
      expect(first, isNotNull);
      final pendingAfterFirst = Map.of(appState.pendingDayValues);

      final second = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async =>
            throw StateError('fetchEvents must not be called'),
        notifications: _RecordingNotifications(),
      );

      expect(second, isNull);
      expect(appState.pendingDayValues, pendingAfterFirst);
    });
  });

  group('T-65 (setting change)', () {
    test('replans immediately, without waiting on FR-17\'s daily lock', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 10);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(result, isNotNull);
      expect(appState.pendingDayValues['2026-03-11'], isNotNull);
    });

    test('a longer sleep goal moves the bedtime earlier', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      final short = _RecordingNotifications();
      appState.sleepGoal = const TimeOfDay(hour: 6, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 0);
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: short,
      );

      final long = _RecordingNotifications();
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: long,
      );

      expect(long.scheduledDates.last!.isBefore(short.scheduledDates.last!),
          isTrue);
    });
  });

  group('runCheckpointSafely', () {
    test('a failing calendar access does not propagate', () async {
      final appState = await _freshAppState();

      // Throws NO exception outward - a propagating error here would abort
      // the app start, or crash the triggering UI.
      final result = await runCheckpointSafely(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async =>
            throw StateError('calendar plugin unavailable'),
        notifications: _RecordingNotifications(),
      );

      expect(result, isNull);
    });

    test(
        'FR-16\'s hook is scheduled even when the replan itself fails',
        () async {
      // Otherwise a fresh install would permanently have no bedtime
      // notification after a calendar error - and thus no checkpoint 2.
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await runCheckpointSafely(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => throw StateError('broken'),
        notifications: notifications,
      );

      expect(notifications.callCount, 1);
    });
  });

  // Ported from replan_notifications_test.dart: there, the reporting path
  // was checked via injected `checkpoint`/`report` seams that no longer
  // exist. Now the test runs through the real wiring - stronger than before.
  group('T-67: reporting on the recovery path (FR-12)', () {
    test('an appointment discovered late for a concluded day is reported',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      // Day 9 rings, empty calendar -> day 10 planned at 07:00.
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      // Day 11, the app is opened: now an appointment for day 10 (already
      // rung) appears, with a stricter hardFloor.
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(9, 0, day: 11),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [
          Meeting(
            from: _utc(5, 0, day: 10),
            to: _utc(6, 0, day: 10),
            isAllDay: false,
            startTimeZone: 'Etc/UTC',
            endTimeZone: 'Etc/UTC',
          )
        ],
        notifications: notifications,
      );

      // One FR-12 report plus the bedtime notification.
      expect(notifications.callCount, 2);
      expect(notifications.ids, contains(isNull),
          reason: 'the FR-12 warning runs without a fixed id');
    });
  });

  group('trigger semantics', () {
    test('only the ring treats today as concluded (T-71)', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(3, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      // Recovery: today (day 9) stays revisable, i.e. it's in the window.
      expect(appState.pendingDayValues['2026-03-09'], isNotNull);
    });

    test('every trigger records the checked time zone offset (FR-16)',
        () async {
      final appState = await _freshAppState();

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 9),
        deviceUtcOffset: const Duration(hours: 2),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(appState.lastCheckedUtcOffset, const Duration(hours: 2));
    });
  });
}
