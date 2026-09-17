import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/utils/notifications.dart';

// docs/TODO.md T-64 (Phase 6): the most severe finding of the consistency pass.
//
// `Handler.onAlarmHandled()` used to call the OLD `Scheduler.scheduleAlarms()`
// (behind `rescheduleOnAlarm`, which defaults to `true` and has no UI). That
// function **first** deletes all ScheduledAlarms (scheduling.dart:164-169)
// and then returns at two places without setting anything new:
// `existingTimes.isEmpty` (:212-215, "No events in calendar. Aborting.") and
// `adjustAlarmTimes() == null` (:254-267). In doing so it reads
// `appState.meetings`, which is typically empty in a process started by the
// alarm.
//
// Sequence in the real app: scheduling-v2 sets the week's alarms -> the user
// dismisses the morning alarm -> onAlarmHandled -> everything deleted, abort
// -> **not a single alarm left**. For an app that promises "guaranteed
// wake-up", the worst possible outcome.
//
// This test would have failed against the unmodified code.

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
  return appState;
}

ScheduledAlarm _alarm(DateTime time, int id) => ScheduledAlarm(
      time: time,
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

void main() {
  test('T-64: a dismiss does NOT delete the planned alarms', () async {
    final appState = await _freshAppState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dayAfter = DateTime.now().add(const Duration(days: 2));
    // The alarm that just rang is itself still in the list - exactly the
    // case in which onAlarmHandled used to kick off scheduleAlarms().
    appState.scheduledAlarms = [_alarm(tomorrow, 501), _alarm(dayAfter, 502)];

    Handler.onAlarmHandled(appState, 501,
        notifications: _SilentNotifications());
    // onAlarmHandled ist fire-and-forget - die Event-Queue mehrfach
    // durchlaufen lassen, damit alles Asynchrone abgeschlossen ist.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(appState.scheduledAlarms.map((a) => a.id), [501, 502],
        reason: 'both planned alarms must be preserved - '
            'got ${appState.scheduledAlarms.map((a) => a.id).toList()}');
  });

  test('T-64: das gilt auch bei leerem Kalender (der reale Fall)', () async {
    final appState = await _freshAppState();
    expect(appState.meetings, isEmpty);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    appState.scheduledAlarms = [_alarm(tomorrow, 503)];

    Handler.onAlarmHandled(appState, 503,
        notifications: _SilentNotifications());
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(appState.scheduledAlarms.length, 1);
  });

  test('die Bettzeit-Erinnerung wird weiterhin neu geplant', () async {
    // Die eine Aufgabe, die onAlarmHandled nach Phase 6 noch hat.
    final appState = await _freshAppState();
    var scheduled = 0;
    final notifications = _CountingNotifications(() => scheduled++);

    Handler.onAlarmHandled(appState, 1, notifications: notifications);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(scheduled, 1);
  });
}

class _CountingNotifications implements Notifications {
  _CountingNotifications(this.onSchedule);

  final void Function() onSchedule;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    onSchedule();
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}
