import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/utils/notifications.dart';

// docs/TODO.md T-64 (Phase 6): der schwerste Befund des Konsistenz-Durchgangs.
//
// `Handler.onAlarmHandled()` rief den ALTEN `Scheduler.scheduleAlarms()` auf
// (hinter `rescheduleOnAlarm`, das per Default `true` ist und keine UI hat).
// Der löscht **zuerst** alle ScheduledAlarms (scheduling.dart:164-169) und
// kehrt danach an zwei Stellen zurück, ohne etwas neu zu setzen:
// `existingTimes.isEmpty` (:212-215, "No events in calendar. Aborting.") und
// `adjustAlarmTimes() == null` (:254-267). Gelesen wird dabei
// `appState.meetings`, das in einem vom Alarm gestarteten Prozess
// typischerweise leer ist.
//
// Ablauf in der echten App: scheduling-v2 setzt die Wochenalarme -> der Nutzer
// dismisst den Morgenalarm -> onAlarmHandled -> alles gelöscht, Abbruch ->
// **kein einziger Alarm mehr**. Für eine App mit dem Versprechen
// "garantiertes Aufwachen" der schlimmstmögliche Ausgang.
//
// Dieser Test hätte gegen den unveränderten Code fehlgeschlagen.

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
  test('T-64: ein Dismiss löscht die geplanten Alarme NICHT', () async {
    final appState = await _freshAppState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dayAfter = DateTime.now().add(const Duration(days: 2));
    // Der gerade geklingelte Alarm ist selbst noch in der Liste - genau der
    // Fall, in dem onAlarmHandled früher scheduleAlarms() anwarf.
    appState.scheduledAlarms = [_alarm(tomorrow, 501), _alarm(dayAfter, 502)];

    Handler.onAlarmHandled(appState, 501,
        notifications: _SilentNotifications());
    // onAlarmHandled ist fire-and-forget - die Event-Queue mehrfach
    // durchlaufen lassen, damit alles Asynchrone abgeschlossen ist.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(appState.scheduledAlarms.map((a) => a.id), [501, 502],
        reason: 'beide geplanten Alarme müssen erhalten bleiben - '
            'bekommen ${appState.scheduledAlarms.map((a) => a.id).toList()}');
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
