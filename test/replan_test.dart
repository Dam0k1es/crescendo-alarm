import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// Phase 4 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge"):
// replan(AppState) - T-60 (Kalender-Cache-Bypass), FR-11, FR-12, FR-15.
// Die Auslöser-Ebene darüber (FR-16 Checkpoint 1, FR-17, T-65) liegt in
// test/checkpoint_test.dart. fetchEvents/now/deviceUtcOffset are injected
// everywhere so these
// tests never touch the real device_calendar plugin or the ambient system
// clock/timezone (same testability rationale as FR-2's deviceUtcOffset
// parameter, see scheduling_v2_test.dart).

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

Meeting _meetingAt(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
    );

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  group('replan (FR-8/T-60/FR-11/FR-12/FR-15)', () {
    test(
        'Kaltstart: erster replan() ohne wunschzeit plant nichts vor dem ersten hardFloor',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      final result = await replan(
        appState,
        now: () => ringDay,
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 30, day: 16))],
      );

      // window = windowStart(=ringDay+1=Tag11)..Tag17.
      expect(appState.pendingDayValues['2026-03-11'], isNull);
      expect(appState.pendingDayValues['2026-03-16'],
          _utc(5, 30, day: 16).millisecondsSinceEpoch);
      expect(appState.lastReplanDate, ringDay);
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);
      expect(result.possiblyMissedAppointment, isFalse);
    });

    test(
        'T-60: zwei replan()-Aufrufe am selben Tag mit unterschiedlichen Kalenderdaten - der zweite gewinnt (FR-11)',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => ringDay,
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
      );
      final firstValue = appState.pendingDayValues['2026-03-11'];
      final counterAfterFirst = appState.gapDayCounter;

      // Gleicher Tag, aber die Kalenderdaten haben sich geändert (z. B. ist
      // ein neuer Termin aufgetaucht) - kein Neustart des Prozesses nötig,
      // um das zu simulieren, nur ein zweiter replan()-Aufruf mit anderen
      // Fake-Daten.
      final result = await replan(
        appState,
        now: () => ringDay,
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(6, 0, day: 11))],
      );

      expect(appState.pendingDayValues['2026-03-11'], isNot(firstValue));
      expect(appState.pendingDayValues['2026-03-11'],
          _utc(6, 0, day: 11).millisecondsSinceEpoch);
      // gapDayCounter darf durch den zweiten Aufruf am selben Tag nicht
      // doppelt fortgeschrieben werden.
      expect(appState.gapDayCounter, counterAfterFirst);
      expect(result.possiblyMissedAppointment, isFalse);
    });

    test(
        'FR-12: verspätet bekannter Termin für den bereits geklingelten Tag löst possiblyMissedAppointment aus, ohne dessen fixen Wert zu ändern',
        () async {
      final appState = await _freshAppState();
      appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

      // Erster Checkpoint (Tag9 klingelt): Kalender komplett leer -> Kaltstart
      // mit wunschzeit, Tag10 (windowStart) wird auf 07:00 gesetzt und ist
      // damit ab jetzt der fixe, tatsächlich geklingelte Wert.
      await replan(
        appState,
        now: () => _utc(0, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
      );
      expect(appState.pendingDayValues['2026-03-10'],
          _utc(7, 0, day: 10).millisecondsSinceEpoch);

      // Zweiter Checkpoint (Tag10 klingelt): der Kalender-Neuread liefert
      // jetzt verspätet einen echten Termin FÜR Tag10 selbst (der bereits
      // geklingelt hat) mit einem strengeren hardFloor (05:00) als der
      // tatsächlich genutzte Wert (07:00).
      final result = await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 10))],
        // Dieses Szenario ist der Ring-Checkpoint: Tag10 hat geklingelt, ist
        // also abgeschlossen (docs/TODO.md T-71).
        todayAlreadyRang: true,
      );

      expect(result.possiblyMissedAppointment, isTrue);
      // FR-12: "der geklingelte Wert bleibt unverändert".
      expect(appState.pendingDayValues['2026-03-10'],
          _utc(7, 0, day: 10).millisecondsSinceEpoch);
    });

    test(
        'Mehrtägige Lücke (z. B. Reboot): gapDayCounter wird für jeden übersprungenen Tag einzeln fortgeschrieben',
        () async {
      final appState = await _freshAppState();

      await replan(
        appState,
        now: () => _utc(0, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );
      expect(appState.gapDayCounter, 1); // Tag9 selbst: kein Termin.

      // 3 Tage Lücke (Tag10, 11, 12 nie einzeln verarbeitet) - alle 3 ohne
      // Termin.
      await replan(
        appState,
        now: () => _utc(0, 0, day: 12),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );
      expect(appState.gapDayCounter, 4); // 1 (Tag9) + 3 (Tag10,11,12).
    });

    // docs/TODO.md T-82: der Merge ohne Prune war für *heute* lasttragend
    // (siehe den Kommentar an der Merge-Stelle), es wurde aber nie etwas
    // entfernt - nach einem Jahr stehen ~365 Einträge in einem JSON-String,
    // den jeder Replan dekodiert, kopiert und wieder kodiert.
    group('T-82: alte Einträge werden begrenzt', () {
      test('Einträge vor gestern verschwinden, gestern und heute bleiben',
          () async {
        final appState = await _freshAppState();
        appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);
        appState.pendingDayValues = {
          '2025-01-01': DateTime.utc(2025, 1, 1, 7).millisecondsSinceEpoch,
          '2026-02-14': DateTime.utc(2026, 2, 14, 7).millisecondsSinceEpoch,
          '2026-03-08': _utc(7, 0, day: 8).millisecondsSinceEpoch,
          '2026-03-09': _utc(7, 0, day: 9).millisecondsSinceEpoch,
          '2026-03-10': _utc(7, 0, day: 10).millisecondsSinceEpoch,
        };

        // Ring an Tag10 -> lastConcludedDay = Tag10, Grenze = Tag9.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );

        expect(appState.pendingDayValues.containsKey('2025-01-01'), isFalse);
        expect(appState.pendingDayValues.containsKey('2026-02-14'), isFalse);
        expect(appState.pendingDayValues.containsKey('2026-03-08'), isFalse);
        // Gestern und heute bleiben - heute ist der Anker des nächsten
        // Fensters und trägt bis zum Klingeln noch einen offenen Alarm.
        expect(appState.pendingDayValues.containsKey('2026-03-09'), isTrue);
        expect(appState.pendingDayValues.containsKey('2026-03-10'), isTrue);
        // Und das gesamte neue Fenster.
        expect(appState.pendingDayValues.containsKey('2026-03-17'), isTrue);
        expect(appState.pendingDayValues.length, 9);
      });

      test('die Karte wächst über viele Replans hinweg nicht weiter', () async {
        final appState = await _freshAppState();
        appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

        for (var d = 10; d <= 25; d++) {
          await replan(
            appState,
            now: () => _utc(7, 0, day: d),
            deviceUtcOffset: Duration.zero,
            fetchEvents: (start, end) async => [],
            todayAlreadyRang: true,
          );
        }

        // 7 Fenstertage + gestern + heute; nie mehr, egal wie lange die App
        // schon läuft.
        expect(appState.pendingDayValues.length, lessThanOrEqualTo(9));
        expect(appState.pendingDayInstantAnchored.length,
            lessThanOrEqualTo(9),
            reason: 'die Anker-Karte darf nicht getrennt davon wachsen');
      });

      test('der heutige, noch nicht geklingelte Wert bleibt beim Erholungs-Replan',
          () async {
        // Der Fall, den der Prune auf keinen Fall kaputtmachen darf: heute
        // 07:00 ist geplant, um 03:00 läuft ein Erholungs-Checkpoint. Fiele
        // der heutige Eintrag weg, würde FR-18 den Alarm entfernen.
        final appState = await _freshAppState();
        appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);
        appState.pendingDayValues = {
          '2026-03-10': _utc(7, 0, day: 10).millisecondsSinceEpoch,
        };

        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
        );

        expect(appState.pendingDayValues['2026-03-10'], isNotNull);
      });
    });

    // docs/TODO.md T-78 / FR-9 "Ausnahme: gesetzte wunschzeit": der
    // Endzustand, um den es dabei wirklich geht - ein Nutzer ohne
    // Kalendertermine, aber mit gewünschter Weckzeit, darf nach zwei Wochen
    // nicht ohne Wecker dastehen.
    test('T-78: wunschzeit-Nutzer ohne Termine behält auch nach 14 Tagen Alarme',
        () async {
      final appState = await _freshAppState();
      appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

      for (var d = 9; d <= 22; d++) {
        await replan(
          appState,
          now: () => _utc(7, 0, day: d),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
      }

      // Der Zähler zählt die termin-losen Tage weiterhin ehrlich mit ...
      expect(appState.gapDayCounter, greaterThanOrEqualTo(7));
      // ... aber es ist weiterhin für jeden Fenstertag ein Wert geplant.
      final windowValues = [23, 24, 25, 26, 27, 28, 29]
          .map((d) => appState.pendingDayValues['2026-03-$d'])
          .toList();
      expect(windowValues.every((v) => v != null), isTrue,
          reason: 'kein Fenstertag darf leer sein, bekommen $windowValues');
      expect(windowValues.first, _utc(7, 0, day: 23).millisecondsSinceEpoch);
    });

    // docs/TODO.md T-75: `lastReplanDate` trug zwei Bedeutungen gleichzeitig -
    // FR-17s Tagessperre ("heute schon neu geplant?") UND den Fortschritt der
    // Tagesfortschreibung ("bis zu welchem abgeschlossenen Tag wurde gezählt?").
    // Seit T-71 ist `lastConcludedDay` je nach Auslöser heute oder gestern,
    // `lastReplanDate` wurde aber immer auf heute gesetzt: ein Erholungs-Replan
    // (App-Resume oder Einstellungsänderung vor dem Morgenalarm - ein völlig
    // normaler Vorgang) verbrauchte damit den Marker, ohne fortzuschreiben, und
    // der spätere echte Ring desselben Tages fand `needsDayAdvance == false`.
    // Der Tag war dauerhaft verloren: FR-9 unterzählt, FR-12 meldet nie.
    group('T-75: zwei Replans an einem Tag', () {
      test('Erholung an Tag D, danach Ring an Tag D -> Tag D wird trotzdem gezählt',
          () async {
        final appState = await _freshAppState();

        // Tag9 klingelt.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 9),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.gapDayCounter, 1);

        // Tag10, 03:00 nachts: App wird geöffnet (FR-17-Erholung). Heute hat
        // noch nicht geklingelt, darf also nicht gezählt werden - Tag9 ist
        // bereits verarbeitet, hier passiert korrekt kein Fortschritt.
        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
        );
        expect(appState.gapDayCounter, 1,
            reason: 'die Erholung selbst darf heute nicht zählen (FR-9)');

        // Tag10, 07:00: der echte Alarm klingelt. JETZT ist Tag10
        // abgeschlossen und muss gezählt werden.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.gapDayCounter, 2,
            reason: 'Tag9 und Tag10 sind beide abgeschlossen und termin-los');
      });

      test('FR-12 bleibt nach einer Erholung am selben Tag meldefähig', () async {
        final appState = await _freshAppState();
        appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

        // Tag9 klingelt, leerer Kalender -> Tag10 wird auf 07:00 geplant.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 9),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );
        expect(appState.pendingDayValues['2026-03-10'],
            _utc(7, 0, day: 10).millisecondsSinceEpoch);

        // Erholung um 03:00 an Tag10, Kalender noch leer.
        await replan(
          appState,
          now: () => _utc(3, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
        );

        // Tag10 klingelt um 07:00, und erst jetzt ist der Termin um 05:00
        // bekannt - der Alarm hat ihn also verpasst.
        final result = await replan(
          appState,
          now: () => _utc(7, 0, day: 10),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 10))],
          todayAlreadyRang: true,
        );

        expect(result.possiblyMissedAppointment, isTrue);
      });

      test('FR-17s Tagessperre bleibt davon unberührt', () async {
        final appState = await _freshAppState();

        // Ring an Tag9 setzt beide Marker.
        await replan(
          appState,
          now: () => _utc(7, 0, day: 9),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => [],
          todayAlreadyRang: true,
        );

        // Ein Foreground-Checkpoint an Tag9 selbst ist danach ein No-op.
        // FR-17s Sperre liest weiterhin lastReplanDate - der Ring hat ihn auf
        // heute gesetzt, ein Vordergrund-Auslöser ist also ein No-op (dass die
        // Sperre selbst greift, prüft test/checkpoint_test.dart).
        expect(midnight(appState.lastReplanDate!), _utc(0, 0, day: 9));
      });
    });

    // docs/TODO.md T-71: nur der Ring-Checkpoint darf heute als abgeschlossen
    // behandeln. Für FR-17s Erholung und eine Einstellungsänderung hat heute
    // noch nicht geklingelt - der Tag muss im Fenster bleiben (FR-11) und darf
    // nicht gezählt werden (FR-9).
    test('Erholungs-Replan (todayAlreadyRang=false): heute bleibt im Fenster und wird nicht gezählt',
        () async {
      final appState = await _freshAppState();
      appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(9, 0, day: 10), // 09:00, heute hat NICHT geklingelt
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
      );

      // Fenster beginnt HEUTE, nicht morgen -> heute ist noch revisionierbar.
      expect(appState.pendingDayValues['2026-03-10'], isNotNull);
      // FR-9: heute zählt nicht mit; gezählt wird nur der letzte
      // abgeschlossene Tag (Tag9).
      expect(appState.gapDayCounter, 1);
      expect(appState.lastReplanDate, _utc(0, 0, day: 10));
    });

    test('Ring-Replan (todayAlreadyRang=true): heute ist fix, Fenster beginnt morgen',
        () async {
      final appState = await _freshAppState();
      appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(6, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );

      expect(appState.pendingDayValues['2026-03-10'], isNull); // nicht im Fenster
      expect(appState.pendingDayValues['2026-03-11'], isNotNull);
    });

    test('T-74c: der allererste Replan meldet keinen verpassten Termin', () async {
      final appState = await _freshAppState();

      final result = await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 9))],
        todayAlreadyRang: true,
      );

      // Ohne Vorgeschichte gibt es keinen "vom letzten Alarm verpassten"
      // Termin - vorher war das eine Falschmeldung beim ersten App-Start.
      expect(result.possiblyMissedAppointment, isFalse);
    });

    test('FR-15: ein ManualAlarm bleibt von replan() vollkommen unberührt',
        () async {
      final appState = await _freshAppState();
      final manualAlarm = ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0));
      appState.manualAlarms.add(manualAlarm);

      await replan(
        appState,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
      );

      expect(appState.manualAlarms, [manualAlarm]);
      expect(appState.manualAlarms.single.time,
          const TimeOfDay(hour: 3, minute: 0));
    });
  });

  // Die Testgruppen zu runAlarmRingCheckpoint, onAppForegroundCheckpoint und
  // runForegroundCheckpointSafely sind nach test/checkpoint_test.dart
  // gewandert - diese drei Einstiegspunkte sind in runSchedulingCheckpoint()
  // aufgegangen (docs/TODO.md T-87). Die Zusicherungen selbst sind dort
  // unverändert vorhanden, nur der Aufrufweg ist einheitlich. Dort steht auch,
  // warum Checkpoint 1 pendingDayValues bewusst NICHT reinterpretiert: der
  // direkt folgende replan() rechnet jeden noch offenen Tag mit dem frischen
  // Versatz neu und wendet ihn per FR-18 an, was jede Reinterpretation
  // ersetzt. Checkpoint 2 braucht sie genau deshalb, weil er nicht neu planen
  // darf (dessen Gruppe unten).

  group('Fensterbildung (T-74d)', () {
    test('über die Sommerzeit-Umstellung hinweg entstehen 7 verschiedene Tage',
        () async {
      final appState = await _freshAppState();
      // Lokale Marker über die Herbst-Umstellung (Europe/Berlin: 25.10.2026).
      // Mit add(Duration(days:)) kollidierten zwei _isoDate-Schlüssel, ein Tag
      // wurde doppelt geplant, einer nie.
      await replan(
        appState,
        now: () => DateTime(2026, 10, 23, 6, 0), // lokal, nicht UTC
        deviceUtcOffset: const Duration(hours: 2),
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: true,
      );

      final planned = appState.pendingDayValues.keys.toSet();
      for (final day in [24, 25, 26, 27, 28, 29, 30]) {
        expect(planned, contains('2026-10-${day.toString().padLeft(2, '0')}'),
            reason: 'Tag $day fehlt im Fenster');
      }
    });
  });

  group('runTimezoneCheckpoint2 (FR-16 Checkpoint 2)', () {
    test(
        'persistiert den aktuell gelesenen Versatz direkt über SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({'lastCheckedUtcOffsetMinutes': 60});
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        readOffset: () => const Duration(hours: 9),
        prefs: prefs,
      );

      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 9 * 60);
    });

    // FR-16s eigentliche Aufgabe (Phase 5 Schritt 22): auf einen erkannten
    // Versatzwechsel reagieren. Erst durch T-61 (Option B) ist das korrekt
    // möglich - ein wunschzeit-abgeleiteter Wert ist ein Instant, dessen
    // LOKALE Ziffern erhalten bleiben müssen (Alarmuhren-Konvention), ein
    // hardFloor-abgeleiteter behält dagegen seinen Instant (der Termin
    // verschiebt sich nicht). Checkpoint 2 hat keinen Kalenderzugriff, kann
    // das also nicht selbst herleiten - daher der persistierte Marker.
    test('Versatzwechsel: ziffern-verankerte Werte behalten ihre lokalen Ziffern, instant-verankerte ihren Instant',
        () async {
      final digitDay = DateTime.utc(2026, 3, 11, 5, 0); // 07:00 lokal bei +2
      final instantDay = DateTime.utc(2026, 3, 12, 4, 0); // echter Termin
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 120, // +2
        'pendingDayValues': jsonEncode({
          '2026-03-11': digitDay.millisecondsSinceEpoch,
          '2026-03-12': instantDay.millisecondsSinceEpoch,
        }),
        'pendingDayInstantAnchored': jsonEncode({
          '2026-03-11': false,
          '2026-03-12': true,
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        readOffset: () => const Duration(hours: 9),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 12, 0),
      );

      final values = (jsonDecode(prefs.getString('pendingDayValues')!)
          as Map<String, dynamic>);
      // 07:00 lokal bleibt 07:00 lokal, jetzt unter +9 -> 22:00 UTC am Vortag.
      expect(values['2026-03-11'],
          DateTime.utc(2026, 3, 10, 22, 0).millisecondsSinceEpoch);
      // Der Termin-Tag bleibt exakt derselbe Instant.
      expect(values['2026-03-12'], instantDay.millisecondsSinceEpoch);
      expect(prefs.getInt('lastCheckedUtcOffsetMinutes'), 9 * 60);
    });

    test('unveränderter Versatz -> kein Wert wird angetastet', () async {
      final value = DateTime.utc(2026, 3, 11, 5, 0);
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 120,
        'pendingDayValues':
            jsonEncode({'2026-03-11': value.millisecondsSinceEpoch}),
        'pendingDayInstantAnchored': jsonEncode({'2026-03-11': false}),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        readOffset: () => const Duration(hours: 2),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 12, 0),
      );

      final values = (jsonDecode(prefs.getString('pendingDayValues')!)
          as Map<String, dynamic>);
      expect(values['2026-03-11'], value.millisecondsSinceEpoch);
    });

    test('bereits vergangene (geklingelte) Werte bleiben unverändert', () async {
      final past = DateTime.utc(2026, 3, 9, 5, 0);
      SharedPreferences.setMockInitialValues({
        'lastCheckedUtcOffsetMinutes': 120,
        'pendingDayValues':
            jsonEncode({'2026-03-09': past.millisecondsSinceEpoch}),
        'pendingDayInstantAnchored': jsonEncode({'2026-03-09': false}),
      });
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        readOffset: () => const Duration(hours: 9),
        prefs: prefs,
        now: () => DateTime.utc(2026, 3, 10, 12, 0),
      );

      final values = (jsonDecode(prefs.getString('pendingDayValues')!)
          as Map<String, dynamic>);
      expect(values['2026-03-09'], past.millisecondsSinceEpoch);
    });

    test(
        'schreibt denselben SharedPreferences-Key wie AppState.lastCheckedUtcOffset (isolate-sicher lesbar)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await runTimezoneCheckpoint2(
        readOffset: () => const Duration(hours: 5),
        prefs: prefs,
      );

      final appState = AppState();
      await appState.initialized;
      expect(appState.lastCheckedUtcOffset, const Duration(hours: 5));
    });
  });
}
