import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/utils/do_not_disturb.dart'
    show doNotDisturbTargetWakeUpKey;
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

  test(
      'T-188 (maintainer device report): a bedtime already in the past does '
      'NOT get caught up immediately - unlike the sleep reminder, activation '
      'is a real, active effect, not a passive notification', () async {
    // Regression: this used to mirror scheduleSleepReminder's own T-110
    // "catch up ASAP" behavior (pushIntoFutureIfPast -> now + 2 minutes),
    // which is fine for a suppressed, passive reminder notification but
    // wrong here - it silenced the maintainer's phone within minutes of
    // turning the toggle on in the middle of the day, nowhere near an
    // actual bedtime, because the next wake-up happened to be sooner than
    // the configured sleep goal.
    final appState = await _freshAppState();
    appState.doNotDisturbEnabled = true;
    final now = DateTime.now();
    // Next wake in 5 hours, sleep goal 9 hours -> bedtime 4 hours ago.
    appState.pendingDayValues = {
      isoDate(now.add(const Duration(hours: 5))):
          now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
    };
    appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
    final notifications = _RecordingNotifications();

    await scheduleDoNotDisturbActivation(appState, notifications: notifications);

    expect(notifications.callCount, 0,
        reason: 'a missed bedtime must not activate Do Not Disturb right '
            'now - the next checkpoint trigger recomputes a genuine future '
            'window once one actually exists');
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
