import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// Regressionen aus der unabhaengigen Spec-Pruefung (2026-09-11).
//
// Diese Datei ist bewusst von `scheduling_v2_test.dart` getrennt: dort steht im
// Kopf die Zusage "Every test case here is taken verbatim (same numbers) from
// the 'Test:' bullets under the matching FR in the spec", und die soll wahr
// bleiben. Die Faelle hier sind aus dem FR-Text *abgeleitet*, nicht aus einem
// Test-Bullet abgeschrieben - sie decken genau die Luecken, die die Pruefung
// gefunden hat, weil die Spec ihre eigenen Bullets nur fuer den jeweils
// einfachsten Fall durchrechnet.
//
// Jeder Fall nennt die Kennung, unter der er in docs/TODO.md gefuehrt wird.

DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 1, day, hour, minute);

Meeting _meetingAt(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
    );

void main() {
  group('FR-5 Schritt 2: ein ΔT=0-Punkt beendet den Run bei sich (T-104)', () {
    // Der Spec-Satz kennt keinen Positionsvorbehalt:
    //
    //   "Ein Punkt mit `ΔT=0` relativ zu `A` beendet den Run sofort bei sich
    //    selbst - zaehlt fuer keine Richtung als kompatibel, wird NIE mit einem
    //    Folgepunkt zusammengefasst."
    //
    // Der spec-eigene Test-Bullet stellt den ΔT=0-Punkt an Position 1
    // (`A=07:00, t1(Di)=07:00, t2(Fr)=09:00`) - also genau dorthin, wo eine
    // Pruefung von `points.first` allein schon ausreicht. Steht er weiter
    // hinten, traegt derselbe Satz trotzdem.

    test('ΔT=0 an Position 2 beendet den Run ebenso wie an Position 1', () {
      final result = groupTarget(
        anchor: _utc(7, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(8, 0, day: 2)),
          HardFloorPoint(dayOffset: 2, value: _utc(7, 0, day: 3)), // ΔT = 0
          HardFloorPoint(dayOffset: 3, value: _utc(5, 0, day: 4)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      // Der Run darf nicht ueber den ΔT=0-Punkt hinaus zusammengefasst werden.
      expect(result.dayOffset, 2);
      expect(result.value, _utc(7, 0, day: 3));
    });

    test('der spec-eigene Fall (ΔT=0 an Position 1) bleibt unveraendert', () {
      final result = groupTarget(
        anchor: _utc(7, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(7, 0, day: 2)), // ΔT = 0
          HardFloorPoint(dayOffset: 4, value: _utc(9, 0, day: 5)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.dayOffset, 1);
    });

    test('ohne ΔT=0-Punkt wird weiterhin bis zum letzten Punkt gruppiert', () {
      // Gegenprobe: die Aenderung darf FR-5 Schritt 1 nicht beschneiden.
      // Spec-Bullet 1: A=08:00, t1(Tag2)=07:00, t2(Tag4)=06:00 -> ein Run ueber
      // beide. Hier mit denselben Zahlen, nur zur Absicherung gegen eine
      // Ueberkorrektur.
      final result = groupTarget(
        anchor: _utc(8, 0),
        points: [
          HardFloorPoint(dayOffset: 2, value: _utc(7, 0, day: 3)),
          HardFloorPoint(dayOffset: 4, value: _utc(6, 0, day: 5)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.dayOffset, 4);
    });

    test('ein ΔT=0-Punkt schrumpft weiter, wenn er einen Zwischenpunkt verletzt',
        () {
      // Schritt 2 begrenzt den Run nach oben; Schritt 1s Schrumpfung bleibt
      // darunter wirksam. Anker 09:00, t1(Tag1)=06:00 (streng),
      // t2(Tag2)=09:00 (ΔT=0). Die Verteilung A->t2 ist flach bei 09:00 und
      // verletzt t1 (09:00 liegt nach 06:00) -> t_m muss auf t1 schrumpfen.
      final result = groupTarget(
        anchor: _utc(9, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(6, 0, day: 2)),
          HardFloorPoint(dayOffset: 2, value: _utc(9, 0, day: 3)), // ΔT = 0
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.dayOffset, 1);
    });
  });

  group('FR-6: die Overrun-Meldung darf auch bei N=1 nicht ausfallen (T-105)',
      () {
    // FR-6, Meldepflicht:
    //
    //   "Bei jeder Ueberschreitung von `maxDailyDelta` (`N=1` ODER verteilt)
    //    wird der Nutzer einmalig benachrichtigt."
    //
    // und der zugehoerige durchgerechnete Fall:
    //
    //   "Test (Overrun, `N=1`): A=08:00, F=02:00, N=1, maxDailyDelta=60min
    //    -> voller 6h-Sprung, Benachrichtigung - kein Spezifikationsfehler."
    //
    // Die Ausnahme, die FR-6 fuer `N=1` gewaehrt, betrifft die *Sprunghoehe*
    // ("kein Verteilen moeglich"), nicht die Meldung. `distribute` setzt die
    // Flagge korrekt; der Weg, auf dem ein Tag seinen eigenen `hardFloor`
    // direkt zugewiesen bekommt, lief bisher an `distribute` vorbei.
    //
    // Betroffen ist genau `window[0]`: fuer jeden spaeteren Fenstertag laeuft
    // der Vortag noch durch FR-7s Pruefung, die den Rest-Sprung entweder klein
    // haelt oder dort einen Run startet (und dann meldet `distribute`).
    // `window[0]`s Anker ist der gestern geklingelte Wert - fuer den findet
    // keine solche Pruefung mehr statt.

    test('einziger Termin auf window[0], Sprung groesser als maxDailyDelta',
        () {
      final window = List.generate(3, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        // gestern geklingelt um 07:00
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: [_meetingAt(_utc(1, 0, day: 1))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      // Der Wert selbst ist FR-konform: FR-2s Obergrenze zwingt auf 01:00,
      // und FR-6 erlaubt den vollen Sprung, weil N=1 ist.
      expect(result.valuesByDay[window[0]], _utc(1, 0, day: 1));
      // Gemeldet werden muss er trotzdem: 6h > 30min.
      expect(result.overrunNotificationNeeded, isTrue);
    });

    test('derselbe Aufbau mit kleinem Sprung meldet nicht', () {
      // Gegenprobe gegen eine Ueberkorrektur: 20min <= 30min.
      final window = List.generate(3, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: [_meetingAt(_utc(6, 40, day: 1))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 40, day: 1));
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test('ein Sprung genau auf maxDailyDelta meldet nicht', () {
      // FR-6s Bedingung ist "> maxDailyDelta", die Grenze selbst ist erlaubt.
      final window = List.generate(3, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: [_meetingAt(_utc(6, 30, day: 1))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      expect(result.overrunNotificationNeeded, isFalse);
    });
  });

  group('FR-9: das Ventil meldet sich, solange sein Zustand besteht (T-107)', () {
    // FR-9:
    //
    //   "Erreicht der Zaehler >= 7, wird automatische Fortschreibung gestoppt
    //    und der Nutzer benachrichtigt."
    //
    // Genau EINE Ausnahme nennt die Spec: "Das Ventil greift nur, wenn keine
    // `wunschzeit` gesetzt ist." FR-10 regelt ausschliesslich die *Werte* bei
    // fehlendem Anker ("Ohne: kein Alarm geplant"), nicht die Meldung.
    //
    // Genau dort lag der Fehler: sobald das Ventil das Fenster einmal
    // leergeraeumt hatte, war `lastEffectiveWakeTime` am Folgetag `null`, und
    // der Kaltstart-Zweig gab hart `safetyValveTriggered: false` zurueck -
    // obwohl der Zaehler weiterlief und nach wie vor nichts geplant wurde.

    test('ohne Anker, Zaehler 7, keine wunschzeit: Ventil steht', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 7,
      );

      expect(result.safetyValveTriggered, isTrue);
      expect(result.valuesByDay.values.every((v) => v == null), isTrue);
    });

    test('dasselbe mit gesetzter wunschzeit meldet nicht (FR-9s Ausnahme)', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 42,
      );

      expect(result.safetyValveTriggered, isFalse);
      expect(result.valuesByDay.values.every((v) => v != null), isTrue,
          reason: 'FR-9s Ausnahme: mit wunschzeit wird weiter fortgeschrieben');
    });

    test('ohne Anker unterhalb der Schwelle meldet nicht', () {
      // Gegenprobe: die Schwelle selbst bleibt bei >= 7. FR-9s eigener
      // Testfall dazu ("Zaehler steht bei 6 ... kein Ausloesen") war in der
      // Suite bisher nur als Additions-Schleife von `updateGapDayCounter`
      // vertreten, nie als Aufruf von `computeWeekPlan`.
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 6,
      );

      expect(result.safetyValveTriggered, isFalse);
    });

    test('mit Anker bleibt der bisherige Ventilweg unveraendert', () {
      // Gegenprobe gegen eine Ueberkorrektur: der Zweig mit Anker meldet
      // weiterhin genau wie bisher.
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 7,
      );

      expect(result.safetyValveTriggered, isTrue);
    });
  });
}
