import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/utils/sleep_reminder.dart';

// Phase 5 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge", Schritt
// 21): die Schlafengehen-Notification muss IMMER geplant werden - auch wenn
// reminderEnabled=false ist. Vor dieser Änderung hätte dieser Test gegen den
// unveränderten Code fehlgeschlagen (Handler.onAlarmHandled rief
// scheduleNotification nur innerhalb eines `if (appState.reminderEnabled)`
// auf).

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
      'reminderEnabled=false: die Notification wird trotzdem geplant, nur still (kein title/body)',
      () async {
    final appState = await _freshAppState();
    appState.reminderEnabled = false;
    final notifications = _RecordingNotifications();

    Handler.onAlarmHandled(appState, 1, notifications: notifications);
    // onAlarmHandled() ist fire-and-forget (siehe seinen Doc-Kommentar) - kurz
    // die Event-Queue durchlaufen lassen, damit scheduleSleepReminder()s
    // eigene await-Punkte (cancelAllNotifications, dann scheduleNotification)
    // vor der Prüfung abgeschlossen sind.
    await Future<void>.delayed(Duration.zero);

    expect(notifications.callCount, 1);
    expect(notifications.lastTitle, isNull);
    expect(notifications.lastBody, isNull);
    expect(notifications.lastScheduledDate, isNotNull);
  });

  test('reminderEnabled=true: die Notification wird sichtbar geplant', () async {
    final appState = await _freshAppState();
    appState.reminderEnabled = true;
    final notifications = _RecordingNotifications();

    Handler.onAlarmHandled(appState, 1, notifications: notifications);
    await Future<void>.delayed(Duration.zero);

    expect(notifications.callCount, 1);
    expect(notifications.lastTitle, isNotNull);
    expect(notifications.lastBody, isNotNull);
  });

  // Gefunden bei der unabhängigen Prüfung von Phase 5: setSleepReminder() lief
  // bisher NUR aus dem Reminder-Toggle heraus und Handler.onAlarmHandled NUR
  // nach einem In-App-Dismiss - auf einem frischen Install (reminderEnabled
  // defaultet auf false, kein Toggle je berührt, kein Alarm je gedismisst)
  // wurde also NIE eine Notification geplant, obwohl FR-16 Checkpoint 2 dafür
  // von Anfang an einen Aufhänger braucht. Regressionstest zuerst (schlägt
  // gegen den unveränderten Code fehl, da scheduleSleepReminder() dort noch
  // nicht existiert).
  group('scheduleSleepReminder (Cold-Start-Regression)', () {
    test(
        'frischer AppState, kein Toggle berührt, kein Alarm gedismisst -> Notification wird trotzdem geplant',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.callCount, 1);
      expect(notifications.lastTitle, isNull);
      expect(notifications.lastBody, isNull);
      expect(notifications.lastScheduledDate, isNotNull);
    });

    // Gefunden bei der erneuten Prüfung des obigen Fixes: das Zusammenlegen
    // der drei Aufrufstellen hatte cancelAllNotifications() (global,
    // AwesomeNotifications().cancelAll()) unbeabsichtigt an zwei neue Stellen
    // gebracht (App-Start, Alarm-Dismiss) - das riskiert, gerade erst vom
    // (unawaited) Replan-Checkpoint erzeugte FR-6/FR-9/FR-12-Warnungen sofort
    // wieder zu verschlucken. Cancel muss auf die Sleep-Reminder-Notification
    // selbst beschränkt bleiben (per fester ID), nicht global.
    // docs/TODO.md T-61: die Schlafenszeit wird aus einem UTC-getaggten
    // Planwert abgeleitet, NotificationCalendar liest aber lokale Ziffern -
    // ohne Umrechnung würde Checkpoint 2 zur falschen lokalen Zeit feuern.
    test(
        'der geplante Zeitpunkt wird lokal übergeben, ohne den realen Moment zu verschieben',
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
        reason: 'derselbe reale Moment erwartet, '
            'bekommen ${notifications.lastScheduledDate}',
      );
    });

    test(
        'storniert nur die vorherige Sleep-Reminder-Notification (per fester ID), nie alle Notifications',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.cancelAllCount, 0);
      expect(notifications.cancelledIds, [sleepReminderNotificationId]);
      expect(notifications.lastScheduledId, sleepReminderNotificationId);
    });
  });


  group('die Bettzeit darf nie in der Vergangenheit geplant werden (T-110)', () {
    // FR-16 haengt seinen zweiten Checkpoint an diese Notification:
    //
    //   "Voraussetzung (gebaut): eine NotificationContent ohne title/body,
    //    die `onNotificationCreatedMethod` ausloest."
    //
    // `scheduleSleepReminder` stornierte die vorhandene aber bedingungslos und
    // plante dann neu - auch fuer einen Zeitpunkt, der schon vorbei ist. Ist
    // `sleepGoal + reminderDuration` groesser als der Abstand bis zum naechsten
    // Weckzeitpunkt, ist die berechnete Bettzeit vergangen.
    //
    // Was Android damit macht, ist nachgelesen, nicht vermutet: in
    // `AndroidAwnCore-0.12.1.aar` liefert `CronUtils.getNextCalendar` fuer
    // jedes Ergebnis vor "jetzt" `null`, `NotificationScheduler.doInBackground`
    // ruft daraufhin `cancelSchedule`, loggt "Date is not more valid." und
    // bricht ab - das Created-Ereignis wird nur im Nicht-null-Zweig gesendet.
    // Die alte Notification ist zu dem Zeitpunkt bereits storniert. Ergebnis:
    // fuer diese Nacht laeuft FR-16s Checkpoint 2 gar nicht, also wird ein
    // untertags eingetretener Zeitzonenwechsel erst beim Klingeln bemerkt -
    // genau das Szenario, gegen das der zweite Checkpoint gebaut wurde.

    test('vergangene Bettzeit: der Aufhaenger wird trotzdem in die Zukunft gelegt',
        () async {
      final appState = await _freshAppState();
      final now = DateTime.now();

      // Naechster Weckzeitpunkt in 5 Stunden, Schlafziel 9 Stunden
      // -> Bettzeit vor 4 Stunden.
      appState.pendingDayValues = {
        isoDate(now.add(const Duration(hours: 5))):
            now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
      };
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 0);

      final notifications = _RecordingNotifications();
      await scheduleSleepReminder(appState, notifications: notifications);

      expect(notifications.callCount, 1,
          reason: 'ohne neue Notification haette FR-16 keinen Aufhaenger mehr');
      expect(notifications.lastScheduledDate, isNotNull);
      expect(notifications.lastScheduledDate!.isAfter(now), isTrue,
          reason: 'ein vollstaendig bestimmtes Datum in der Vergangenheit hat '
              'keinen naechsten gueltigen Termin - Android verwirft es');
    });

    test('vergangene Bettzeit: der Aufhaenger ist still, auch bei aktiver Erinnerung',
        () async {
      // Eine sichtbare "geh schlafen"-Meldung Stunden nach dem gemeinten
      // Zeitpunkt waere irrefuehrend. FR-16 trennt Sichtbarkeit ausdruecklich
      // vom Aufhaenger; hier ist nur der Aufhaenger noch sinnvoll.
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

    test('zukuenftige Bettzeit bleibt unveraendert sichtbar und puenktlich',
        () async {
      // Gegenprobe gegen eine Ueberkorrektur.
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
          reason: 'rund 8 Stunden voraus, nicht vorgezogen');
    });
  });
}
