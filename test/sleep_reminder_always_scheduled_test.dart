import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/utils/sleep_reminder.dart';

// Phase 5 (docs/scheduling-v2-spec.md, "Implementation order", step
// 21): the bedtime notification must ALWAYS be scheduled - even when
// reminderEnabled=false. Before this change, this test would have failed
// against the unmodified code (Handler.onAlarmHandled only called
// scheduleNotification inside an `if (appState.reminderEnabled)`).

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
  test(
      'reminderEnabled=false: the notification is scheduled anyway, just silently (no title/body)',
      () async {
    final appState = await _freshAppState();
    appState.reminderEnabled = false;
    final notifications = _RecordingNotifications();

    Handler.onAlarmHandled(appState, 1, notifications: notifications);
    // onAlarmHandled() is fire-and-forget (see its doc comment) - briefly let
    // the event queue run through, so scheduleSleepReminder()'s own await
    // points (cancelAllNotifications, then scheduleNotification) are done
    // before the check.
    await Future<void>.delayed(Duration.zero);

    expect(notifications.callCount, 1);
    expect(notifications.lastTitle, isNull);
    expect(notifications.lastBody, isNull);
    expect(notifications.lastScheduledDate, isNotNull);
  });

  test('reminderEnabled=true: the notification is scheduled visibly', () async {
    final appState = await _freshAppState();
    appState.reminderEnabled = true;
    final notifications = _RecordingNotifications();

    Handler.onAlarmHandled(appState, 1, notifications: notifications);
    await Future<void>.delayed(Duration.zero);

    expect(notifications.callCount, 1);
    expect(notifications.lastTitle, isNotNull);
    expect(notifications.lastBody, isNotNull);
  });

  // Found during Phase 5's independent review: setSleepReminder() used to
  // run ONLY out of the reminder toggle, and Handler.onAlarmHandled ONLY
  // after an in-app dismiss - on a fresh install (reminderEnabled defaults
  // to false, no toggle ever touched, no alarm ever dismissed), NO
  // notification was ever scheduled, even though FR-16 checkpoint 2 needs a
  // hook for it from the very start. Regression test first (fails against
  // the unmodified code, since scheduleSleepReminder() doesn't exist there
  // yet).
  group('scheduleSleepReminder (cold-start regression)', () {
    test(
        'fresh AppState, no toggle touched, no alarm dismissed -> a notification is scheduled anyway',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.callCount, 1);
      expect(notifications.lastTitle, isNull);
      expect(notifications.lastBody, isNull);
      expect(notifications.lastScheduledDate, isNotNull);
    });

    // Found on re-reviewing the fix above: consolidating the three call
    // sites had unintentionally brought cancelAllNotifications() (global,
    // AwesomeNotifications().cancelAll()) to two new spots (app start, alarm
    // dismiss) - risking swallowing FR-6/FR-9/FR-12 warnings that the
    // (unawaited) replan checkpoint had just produced. Cancel must stay
    // scoped to the sleep-reminder notification itself (by a fixed id), not
    // global.
    // docs/TODO.md T-61: the bedtime is derived from a UTC-tagged planned
    // value, but NotificationCalendar reads local digits - without
    // conversion, checkpoint 2 would fire at the wrong local time.
    test(
        'the scheduled instant is passed as local, without shifting the real moment',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();
      final wakeUp = DateTime.now().toUtc().add(const Duration(hours: 10));
      final iso = '${wakeUp.year}-${wakeUp.month.toString().padLeft(2, '0')}'
          '-${wakeUp.day.toString().padLeft(2, '0')}';
      appState.pendingDayValues = {iso: wakeUp.millisecondsSinceEpoch};
      appState.sleepGoal = const TimeOfDay(hour: 8, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 30);

      await scheduleSleepReminder(appState, notifications: notifications);

      final expected = wakeUp
          .subtract(const Duration(hours: 8))
          .subtract(const Duration(minutes: 30));
      expect(notifications.lastScheduledDate!.isUtc, isFalse);
      expect(
        notifications.lastScheduledDate!.difference(expected).abs().inMinutes,
        lessThanOrEqualTo(1),
        reason: 'expected the same real moment, '
            'got ${notifications.lastScheduledDate}',
      );
    });

    test(
        'only cancels the previous sleep-reminder notification (by a fixed id), never all notifications',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.cancelAllCount, 0);
      expect(notifications.cancelledIds, [sleepReminderNotificationId]);
      expect(notifications.lastScheduledId, sleepReminderNotificationId);
    });
  });


  group('bedtime must never be scheduled in the past (T-110)', () {
    // FR-16 hangs its second checkpoint off this notification:
    //
    //   "Precondition (built): a NotificationContent without title/body,
    //    that triggers `onNotificationCreatedMethod`."
    //
    // `scheduleSleepReminder` used to cancel the existing one unconditionally
    // and then reschedule - even for an instant that has already passed. If
    // `sleepGoal + reminderDuration` is greater than the distance to the next
    // wake instant, the computed bedtime is in the past.
    //
    // What Android does with it is read from the source, not guessed: in
    // `AndroidAwnCore-0.12.1.aar`, `CronUtils.getNextCalendar` returns `null`
    // for any result before "now", `NotificationScheduler.doInBackground`
    // then calls `cancelSchedule`, logs "Date is not more valid." and
    // aborts - the Created event is only sent on the non-null branch. The
    // old notification is already cancelled by that point. Result: for that
    // night, FR-16's checkpoint 2 doesn't run at all, so a time zone change
    // that happened during the day is only noticed at the next ring -
    // exactly the scenario the second checkpoint was built against.

    test('past bedtime: the hook is placed in the future anyway',
        () async {
      final appState = await _freshAppState();
      final now = DateTime.now();

      // Next wake instant in 5 hours, sleep goal 9 hours
      // -> bedtime 4 hours ago.
      appState.pendingDayValues = {
        isoDate(now.add(const Duration(hours: 5))):
            now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 0);

      final notifications = _RecordingNotifications();
      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.callCount, 1,
          reason: 'without a new notification, FR-16 would have no hook left');
      expect(notifications.lastScheduledDate, isNotNull);
      expect(notifications.lastScheduledDate!.isAfter(now), isTrue,
          reason: 'a fully determined date in the past has no next valid '
              'occurrence - Android discards it');
    });

    test('past bedtime: the hook is silent, even with the reminder active',
        () async {
      // A visible "time to sleep" message hours after the intended instant
      // would be misleading. FR-16 explicitly separates visibility from the
      // hook; here only the hook still makes sense.
      final appState = await _freshAppState();
      final now = DateTime.now();
      appState.pendingDayValues = {
        isoDate(now.add(const Duration(hours: 5))):
            now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 0);
      appState.reminderEnabled = true;

      final notifications = _RecordingNotifications();
      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.lastTitle, isNull);
      expect(notifications.lastBody, isNull);
    });

    test('a future bedtime stays visible and on time, unchanged',
        () async {
      // Counter-check against over-correction.
      final appState = await _freshAppState();
      final now = DateTime.now();
      appState.pendingDayValues = {
        isoDate(now.add(const Duration(hours: 10))):
            now.add(const Duration(hours: 10)).millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 2, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 0);
      appState.reminderEnabled = true;

      final notifications = _RecordingNotifications();
      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.lastTitle, isNotNull);
      expect(notifications.lastScheduledDate!.isAfter(now.add(const Duration(hours: 7))),
          isTrue,
          reason: 'around 8 hours ahead, not brought forward');
    });
  });
}
