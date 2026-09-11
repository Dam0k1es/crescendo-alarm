import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/notifications.dart';

// Regressionen aus der unabhaengigen Spec-Pruefung (2026-09-11), Ebene
// Checkpoint-Ausloeser. Domaene und replan() liegen in
// scheduling_v2_audit_test.dart bzw. replan_audit_test.dart.

class _SilentNotifications implements Notifications {
  int scheduleCount = 0;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    scheduleCount++;
    return id ?? 1;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> cancelAllNotifications() async {}
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
  tzdata.initializeTimeZones();

  group('FR-17: die Tagessperre prueft "!= heute", nicht ">= heute" (T-109)',
      () {
    // FR-17 woertlich:
    //
    //   "Ist `lastReplanDate` != heutiges Kalenderdatum (Geraete-Zeitzone):
    //    sofort, vor jeder UI-Interaktion, derselbe Ablauf wie FR-8s
    //    Ring-Checkpoint [...] Sonst: kein zusaetzlicher Checkpoint."
    //
    // Der Code las `!midnight(last).isBefore(midnight(jetzt))`, also ">=".
    // Fuer ein `lastReplanDate` in der ZUKUNFT wurde damit uebersprungen,
    // obwohl FR-17 "!=" fordert.
    //
    // In die Zukunft geraet der Marker ohne jedes Zutun der App: er ist ein
    // geraetelokales Ziffern-Datum ohne Klammerung, und ein Zonenwechsel ueber
    // die Datumsgrenze (oder eine Rueckwaertskorrektur der Systemuhr) laesst
    // das lokale Datum zurueckspringen. Genau dann faellt der eine Mechanismus
    // aus, der einen veralteten Plan noch reparieren koennte - und zwar in
    // genau den drei Luecken, fuer die FR-17 gebaut ist (Reboot, Force-Quit,
    // ausgefallenes taegliches Klingeln), in denen es keinen Ring gibt, der
    // den Marker nebenbei repariert.

    test('lastReplanDate morgen: der Vordergrund-Checkpoint laeuft', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _tomorrowOf(DateTime.utc(2026, 3, 10));

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => DateTime.utc(2026, 3, 10, 9, 0),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const <Meeting>[],
        notifications: _SilentNotifications(),
      );

      expect(result, isNotNull,
          reason: 'FR-17: != heute -> voller Checkpoint');
      expect(appState.lastReplanDate, DateTime.utc(2026, 3, 10));
    });

    test('lastReplanDate heute: weiterhin ein No-op', () async {
      // Gegenprobe: FR-17s eigentlicher Zweck (hoechstens einmal taeglich)
      // darf nicht verlorengehen.
      final appState = await _freshAppState();
      appState.lastReplanDate = DateTime.utc(2026, 3, 10);

      var fetches = 0;
      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => DateTime.utc(2026, 3, 10, 20, 0),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async {
          fetches++;
          return const <Meeting>[];
        },
        notifications: _SilentNotifications(),
      );

      expect(result, isNull);
      expect(fetches, 0);
    });

    test('lastReplanDate gestern: laeuft weiterhin', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = DateTime.utc(2026, 3, 9);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => DateTime.utc(2026, 3, 10, 9, 0),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const <Meeting>[],
        notifications: _SilentNotifications(),
      );

      expect(result, isNotNull);
    });

    test('echter Datumsruecksprung: Apia (+13) nach Pago Pago (-11)', () async {
      // Der Fall, der das ueberhaupt erst erzeugt - als echte IANA-Zonen, nicht
      // als UTC-Fixture: auf dieser UTC+0-VM kann ein `DateTime.utc`-Fixture
      // einen Datumsruecksprung gar nicht darstellen.
      final apia = tz.getLocation('Pacific/Apia');
      final pago = tz.getLocation('Pacific/Pago_Pago');

      final beforeFlight = tz.TZDateTime(apia, 2026, 3, 10, 8, 0);
      // Derselbe Instant, in Pago Pago gelesen: 24 Stunden Versatzdifferenz,
      // also der 09.03. - ein Kalendertag ZURUECK, obwohl die Zeit vorwaerts
      // laeuft.
      final afterFlight =
          tz.TZDateTime.from(beforeFlight.add(const Duration(hours: 2)), pago);

      expect(afterFlight.day, lessThan(beforeFlight.day),
          reason: 'Fixture-Kontrolle: das lokale Datum springt wirklich zurueck');
      expect(afterFlight.isAfter(beforeFlight), isTrue,
          reason: 'Fixture-Kontrolle: der zweite Moment liegt real spaeter');

      final appState = await _freshAppState();
      var fetches = 0;
      Future<List<Meeting>> fetch(DateTime start, DateTime end) async {
        fetches++;
        return const <Meeting>[];
      }

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => beforeFlight,
        deviceUtcOffset: beforeFlight.timeZoneOffset,
        fetchEvents: fetch,
        notifications: _SilentNotifications(),
      );
      expect(fetches, 1, reason: 'der erste Checkpoint laeuft');

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => afterFlight,
        deviceUtcOffset: afterFlight.timeZoneOffset,
        fetchEvents: fetch,
        notifications: _SilentNotifications(),
      );

      expect(result, isNotNull,
          reason: 'FR-17: das lokale Datum ist ein anderes -> Checkpoint');
      expect(fetches, 2,
          reason: 'und mit ihm ein ungecachter Kalender-Neuread');
    });
  });
}

DateTime _tomorrowOf(DateTime day) => day.add(const Duration(days: 1));
