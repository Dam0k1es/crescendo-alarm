import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/utils/do_not_disturb.dart'
    show doNotDisturbPreviousFilterKey, doNotDisturbTargetWakeUpKey;
import 'package:crescendo_alarm/utils/do_not_disturb_channel.dart'
    show interruptionFilterAlarms, interruptionFilterAll, interruptionFilterPriority;
import 'package:crescendo_alarm/utils/do_not_disturb_schedule.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/sleep_reminder.dart' show sleepReminderNotificationId;

// docs/TODO.md T-184 (maintainer request): "in der Schlafenszeit (sleep
// goal) vor dem Wecker (ohne reminder Zeit) benachrichtigungen
// deaktivieren" - Do Not Disturb activates at the sleep-goal-derived
// bedtime itself (wake time - sleepGoal), NOT further reduced by
// reminderDuration the way the separate bedtime-reminder notification is -
// those are two different instants, scheduled independently.

class _RecordingNotifications implements Notifications {
  String? lastTitle;
  String? lastBody;
  DateTime? lastScheduledDate;
  int? lastScheduledId;
  int callCount = 0;
  int cancelAllCount = 0;
  final List<int> cancelledIds = [];

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    callCount++;
    lastTitle = title;
    lastBody = body;
    lastScheduledDate = scheduledDate;
    lastScheduledId = id;
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async {
    cancelAllCount++;
  }

  @override
  Future<void> cancelNotification(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> init() async {}
}

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('disabled: nothing is scheduled, any previous one is cancelled',
      () async {
    final appState = await _freshAppState();
    appState.doNotDisturbEnabled = false;
    final notifications = _RecordingNotifications();

    await scheduleDoNotDisturbActivation(appState, notifications: notifications);

    expect(notifications.callCount, 0);
    expect(notifications.cancelAllCount, 0);
    expect(notifications.cancelledIds, [doNotDisturbActivationNotificationId]);
  });

  test('enabled: a silent notification is scheduled at wakeTime - sleepGoal, '
      'NOT further reduced by reminderDuration', () async {
    final appState = await _freshAppState();
    appState.doNotDisturbEnabled = true;
    final wakeUp = DateTime.now().toUtc().add(const Duration(hours: 10));
    appState.pendingDayValues = {
      isoDate(wakeUp): wakeUp.millisecondsSinceEpoch,
    };
    appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
    // Deliberately non-zero, to prove it is NOT subtracted here too.
    appState.reminderDuration = const TimeOfDay(hour: 0, minute: 30);
    final notifications = _RecordingNotifications();

    await scheduleDoNotDisturbActivation(appState, notifications: notifications);

    expect(notifications.callCount, 1);
    expect(notifications.lastTitle, isNull,
        reason: 'a background/silent notification - Do Not Disturb '
            'activation is not something the user needs to see happen');
    expect(notifications.lastBody, isNull);
    expect(notifications.lastScheduledId, doNotDisturbActivationNotificationId);

    final expected = wakeUp.subtract(const Duration(hours: 8));
    expect(notifications.lastScheduledDate!.isUtc, isFalse);
    expect(
      notifications.lastScheduledDate!.difference(expected).abs().inMinutes,
      lessThanOrEqualTo(1),
      reason: 'expected the same real moment (bedtime, no reminder lead '
          'time subtracted), got ${notifications.lastScheduledDate}',
    );
  });

  test('only cancels its own notification (by a fixed id), never all',
      () async {
    final appState = await _freshAppState();
    appState.doNotDisturbEnabled = true;
    final notifications = _RecordingNotifications();

    await scheduleDoNotDisturbActivation(appState, notifications: notifications);

    expect(notifications.cancelAllCount, 0);
    expect(notifications.cancelledIds, [doNotDisturbActivationNotificationId]);
  });

  group('T-189 (maintainer request, supersedes T-188): "sleep time" is the '
      'live window [bedtime, next alarm) - evaluated on every call, not '
      'only via a precisely-timed background notification', () {
    // Maintainer's own definition, verbatim: "Ich will, dass in der
    // schlafenszeit automatisch aktiviert und danach deaktiviert ist. die
    // schlafenszeit ist die zeit die konfiguriert ist VOR dem nächsten
    // alarm in der zukunft." T-188's first attempt ("skip a missed bedtime
    // entirely") got this wrong in two ways an independent review (Günther)
    // found: it left Do Not Disturb permanently off for any user whose
    // Sleep Goal is longer than the actual gap to their next wake-up (a
    // short-turnaround/shift-worker schedule - exactly this app's stated
    // audience), and a later, unrelated checkpoint trigger (a settings
    // change, a calendar resync) after bedtime had passed would cancel an
    // already-correctly-armed notification without replacing it.

    test('now is inside the window (a short-turnaround schedule): '
        'activates immediately, live - even though bedtime is already in '
        'the past', () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final now = DateTime.now();
      // Next wake in 5 hours, sleep goal 9 hours -> bedtime 4 hours ago,
      // but "now" is still before the wake-up - we ARE inside the window.
      appState.pendingDayValues = {
        isoDate(now.add(const Duration(hours: 5))):
            now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      final notifications = _RecordingNotifications();
      final prefs = await SharedPreferences.getInstance();
      int? appliedFilter;

      await scheduleDoNotDisturbActivation(
        appState,
        notifications: notifications,
        prefs: prefs,
        now: () => now,
        getCurrentFilter: () async => interruptionFilterAll,
        setFilter: (f) async {
          appliedFilter = f;
          return true;
        },
      );

      expect(appliedFilter, interruptionFilterAlarms,
          reason: 'inside the configured sleep window is exactly when Do '
              'Not Disturb should be on, regardless of how long ago the '
              'window technically started');
      expect(notifications.callCount, 0,
          reason: 'nothing to schedule for an instant already in the past - '
              'activation already happened live, above');
      expect(prefs.getInt(doNotDisturbTargetWakeUpKey), isNotNull,
          reason: 'the target must still be persisted so a later ring can '
              'be matched against it (isTargetWakeUpRing)');
    });

    test('already active from this feature, still inside the window: '
        'does not re-activate or touch anything redundantly', () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final now = DateTime.now();
      appState.pendingDayValues = {
        isoDate(now.add(const Duration(hours: 5))):
            now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      SharedPreferences.setMockInitialValues(
          {doNotDisturbPreviousFilterKey: interruptionFilterAll});
      final prefs = await SharedPreferences.getInstance();
      var getCurrentFilterCalls = 0;

      await scheduleDoNotDisturbActivation(
        appState,
        notifications: _RecordingNotifications(),
        prefs: prefs,
        now: () => now,
        getCurrentFilter: () async {
          getCurrentFilterCalls++;
          return interruptionFilterAlarms;
        },
        setFilter: (f) async => true,
      );

      expect(getCurrentFilterCalls, 0,
          reason: 'already active - activateDoNotDisturb\'s own idempotency '
              'guard must not re-read/overwrite the real previous state');
    });

    test('a previously-armed cycle whose window has now ended: restores, '
        'if still active from this feature', () async {
      // [nextWakeUpTime] only ever returns future candidates, so a FRESH
      // recompute can never look "ended" - this can only be detected
      // against a PREVIOUSLY PERSISTED target from an earlier call, hence
      // pre-populating it directly here rather than via pendingDayValues.
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final now = DateTime.now();
      final staleTarget = now.subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues({
        doNotDisturbTargetWakeUpKey: staleTarget.millisecondsSinceEpoch,
        doNotDisturbPreviousFilterKey: interruptionFilterPriority,
      });
      final prefs = await SharedPreferences.getInstance();
      // An ordinary, unrelated future cycle for the function to also plan -
      // irrelevant to this assertion, just needs to exist.
      final nextWakeUp = now.toUtc().add(const Duration(hours: 10));
      appState.pendingDayValues = {
        isoDate(nextWakeUp): nextWakeUp.millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      int? restoredTo;

      await scheduleDoNotDisturbActivation(
        appState,
        notifications: _RecordingNotifications(),
        prefs: prefs,
        now: () => now,
        setFilter: (f) async {
          restoredTo = f;
          return true;
        },
      );

      expect(restoredTo, interruptionFilterPriority);
    });

    test('a stale persisted target with no active previous-filter state: '
        'no restore attempted', () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final now = DateTime.now();
      final staleTarget = now.subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues(
          {doNotDisturbTargetWakeUpKey: staleTarget.millisecondsSinceEpoch});
      final prefs = await SharedPreferences.getInstance();
      final nextWakeUp = now.toUtc().add(const Duration(hours: 10));
      appState.pendingDayValues = {
        isoDate(nextWakeUp): nextWakeUp.millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      var setFilterCalls = 0;

      await scheduleDoNotDisturbActivation(
        appState,
        notifications: _RecordingNotifications(),
        prefs: prefs,
        now: () => now,
        setFilter: (f) async {
          setFilterCalls++;
          return true;
        },
      );

      expect(setFilterCalls, 0);
    });

    test('still upcoming, target UNCHANGED since the last call: the '
        'already-armed notification is left alone', () async {
      // The regression an independent review found in T-188's first
      // attempt: any unrelated checkpoint trigger (a settings change, a
      // calendar resync) re-running this must not disturb an
      // already-correct night's schedule.
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final wakeUp = DateTime.now().toUtc().add(const Duration(hours: 10));
      appState.pendingDayValues = {
        isoDate(wakeUp): wakeUp.millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      final prefs = await SharedPreferences.getInstance();
      final first = _RecordingNotifications();
      await scheduleDoNotDisturbActivation(appState,
          notifications: first, prefs: prefs);
      expect(first.callCount, 1, reason: 'sanity check on the first call');

      final second = _RecordingNotifications();
      await scheduleDoNotDisturbActivation(appState,
          notifications: second, prefs: prefs);

      expect(second.callCount, 0);
      expect(second.cancelledIds, isEmpty,
          reason: 'nothing about tonight\'s cycle changed - the existing, '
              'still-correct schedule must not even be cancelled');
    });

    test('still upcoming, target CHANGED since the last call (a real '
        'replan moved the wake-up): the notification IS re-armed',
        () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final firstWakeUp = DateTime.now().toUtc().add(const Duration(hours: 10));
      appState.pendingDayValues = {
        isoDate(firstWakeUp): firstWakeUp.millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      final prefs = await SharedPreferences.getInstance();
      await scheduleDoNotDisturbActivation(appState,
          notifications: _RecordingNotifications(), prefs: prefs);

      final secondWakeUp = DateTime.now().toUtc().add(const Duration(hours: 11));
      appState.pendingDayValues = {
        isoDate(secondWakeUp): secondWakeUp.millisecondsSinceEpoch,
      };
      final second = _RecordingNotifications();
      await scheduleDoNotDisturbActivation(appState,
          notifications: second, prefs: prefs);

      expect(second.callCount, 1,
          reason: 'the underlying wake-up genuinely changed - the old '
              'schedule is now for the wrong instant and must be replaced');
      expect(second.cancelledIds, [doNotDisturbActivationNotificationId]);
    });
  });

  group('T-191 (maintainer request): only manual alarms explicitly opted '
      'in count toward the Do Not Disturb window', () {
    test('a manual alarm that has NOT opted in is ignored, even though it '
        'is earlier than the real Scheduled wake-up', () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      final soonReminder = DateTime.now().add(const Duration(hours: 2));
      final realWakeUp = DateTime.now().toUtc().add(const Duration(hours: 10));
      appState.manualAlarms.add(ManualAlarm(
        time: TimeOfDay(hour: soonReminder.hour, minute: soonReminder.minute),
        countsForDoNotDisturb: false,
      ));
      appState.pendingDayValues = {
        isoDate(realWakeUp): realWakeUp.millisecondsSinceEpoch,
      };
      final notifications = _RecordingNotifications();

      await scheduleDoNotDisturbActivation(appState, notifications: notifications);

      expect(notifications.callCount, 1,
          reason: 'if the un-opted-in manual alarm had wrongly been used as '
              '"the" wake-up, its own bedtime would already be in the past '
              '(now - 6h), which activates live and schedules nothing at '
              'all instead - a callCount of 0 here would itself already be '
              'a symptom of the bug');
      final expectedBedtime = realWakeUp.toLocal().subtract(const Duration(hours: 8));
      expect(
        notifications.lastScheduledDate!.difference(expectedBedtime).abs().inMinutes,
        lessThanOrEqualTo(1),
        reason: 'the un-opted-in manual alarm must not influence the '
            'computed bedtime at all - only the real Scheduled wake-up may',
      );
    });

    test('a manual alarm that HAS opted in is used when it is the earliest '
        'wake-up', () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      appState.sleepGoal = const TimeOfDay(hour: 1, minute: 0);
      final now = DateTime.now();
      final soonManual = now.add(const Duration(hours: 2));
      final laterScheduled = now.toUtc().add(const Duration(hours: 10));
      appState.manualAlarms.add(ManualAlarm(
        time: TimeOfDay(hour: soonManual.hour, minute: soonManual.minute),
        countsForDoNotDisturb: true,
      ));
      appState.pendingDayValues = {
        isoDate(laterScheduled): laterScheduled.millisecondsSinceEpoch,
      };
      final notifications = _RecordingNotifications();

      await scheduleDoNotDisturbActivation(appState, notifications: notifications);

      final expectedBedtime = soonManual.subtract(const Duration(hours: 1));
      expect(
        notifications.lastScheduledDate!.difference(expectedBedtime).abs().inMinutes,
        lessThanOrEqualTo(1),
        reason: 'the opted-in manual alarm is the earliest wake-up and '
            'must be what the bedtime is computed from',
      );
    });
  });

  test('the doNotDisturbActivationNotificationId is a distinct fixed id, '
      'not the sleep-reminder one', () {
    expect(doNotDisturbActivationNotificationId, isNot(sleepReminderNotificationId));
  });

  group('persisted target wake-up (docs/TODO.md T-184, independent review '
      'finding)', () {
    // Handler.handleAlarm reads this back (isTargetWakeUpRing) to tell
    // whether a ring is the one Do Not Disturb was actually scheduled
    // around, as opposed to some unrelated alarm ringing and becoming
    // "final" first.

    test('enabled: persists the WAKE-UP instant (not the bedtime) the '
        'schedule was computed from', () async {
      final appState = await _freshAppState();
      appState.doNotDisturbEnabled = true;
      final wakeUp = DateTime.now().toUtc().add(const Duration(hours: 10));
      appState.pendingDayValues = {
        isoDate(wakeUp): wakeUp.millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      final prefs = await SharedPreferences.getInstance();

      await scheduleDoNotDisturbActivation(appState,
          notifications: _RecordingNotifications(), prefs: prefs);

      final storedMillis = prefs.getInt(doNotDisturbTargetWakeUpKey);
      expect(storedMillis, isNotNull);
      final stored = DateTime.fromMillisecondsSinceEpoch(storedMillis!);
      expect(stored.difference(wakeUp.toLocal()).abs().inMinutes,
          lessThanOrEqualTo(1),
          reason: 'expected the WAKE-UP instant itself, not the bedtime '
              '(wakeUp - sleepGoal) that gets scheduled - got $stored');
    });

    test('disabled: clears any previously persisted target', () async {
      SharedPreferences.setMockInitialValues(
          {doNotDisturbTargetWakeUpKey: 123456});
      final appState = AppState();
      await appState.initialized;
      appState.doNotDisturbEnabled = false;
      final prefs = await SharedPreferences.getInstance();

      await scheduleDoNotDisturbActivation(appState,
          notifications: _RecordingNotifications(), prefs: prefs);

      expect(prefs.getInt(doNotDisturbTargetWakeUpKey), isNull);
    });
  });
}
