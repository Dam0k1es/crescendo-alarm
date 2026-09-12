import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
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

  group('FR-6: die 12-Stunden-Schwelle der Richtungsaufloesung (T-115)', () {
    // FR-6, "Klarstellung ΔT":
    //
    //   "Die Mehrdeutigkeit bei der Richtungsbestimmung wird wie in FR-1
    //    aufgeloest (die Variante mit `|Δ| <= 12h` gewinnt)."
    //
    // Diese Schwelle traegt die gesamte Mitternachtsbehandlung des Moduls -
    // sie ist der Grund, warum "22:00 -> 05:00 am Folgetag" als +7h gelesen
    // wird und nicht als -17h. In der Suite kam sie bisher nicht vor: der
    // groesste gepruefte Abstand lag bei zwei Stunden.
    //
    // Geprueft werden hier die beiden Werte UNMITTELBAR neben der Schwelle.
    // Sie klammern sie beidseitig auf 12:00 +/- eine Minute ein und fangen
    // damit jede Verschiebung oder versehentliche Entfernung der
    // Wraparound-Aufloesung.
    //
    // Der Wert AUF der Schwelle (genau 12:00) fehlt hier mit Absicht: dort
    // erfuellen beide Lesarten `|Δ| <= 12h`, die Regel waehlt also nicht, und
    // der Spec-Text entscheidet den Fall nicht. Ihn hier festzuschreiben
    // hiesse, das Soll selbst zu erfinden. Siehe docs/TODO.md T-115.

    test('11:59 Abstand wird als "frueher" gelesen', () {
      final result = applyGapDayDrift(
        v: _utc(18, 59, day: 1),
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );

      // -11:59 gewinnt gegen +12:01, also rueckwaerts, gedeckelt auf 30min.
      expect(result, _utc(18, 29, day: 2));
    });

    test('12:01 Abstand wird als "spaeter" gelesen', () {
      final result = applyGapDayDrift(
        v: _utc(19, 1, day: 1),
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );

      // +11:59 gewinnt gegen -12:01, also vorwaerts.
      expect(result, _utc(19, 31, day: 2));
    });
  });

  // ---------------------------------------------------------------------
  // Absicherungen (T-118): Eigenschaften, die heute RICHTIG sind, von der
  // Spec eindeutig entschieden werden - und von keinem Test gedeckt waren.
  //
  // Jede einzelne stammt aus einem Fall, dessen Kern eine offene
  // Spec-Entscheidung ist (T-119 bis T-122). Der jeweils entschiedene Teil
  // laesst sich trotzdem festnageln, und das ist die Grundlage, gegen die
  // eine spaetere Entscheidung ueberhaupt formuliert werden kann.
  //
  // Fuer jede ist eine Mutation belegt, die sie rot macht und die heute in
  // der uebrigen Suite unsichtbar bleibt.
  // ---------------------------------------------------------------------

  group('FR-2: Tageszuordnung an der Mitternachtsgrenze (T-118a)', () {
    // FR-2: "Die Geraete-Zeitzone zum Auswertungszeitpunkt - niemals die Zone
    // des Termins selbst - entscheidet, welchem Kalendertag der Instant
    // zugeordnet wird."
    //
    // Bei KONSTANTEM Versatz ist das eindeutig entschieden. Der vorhandene
    // FR-2-Zeitzonentest prueft die *Herkunft* des Versatzes, nie dessen
    // Vorzeichen und nie eine Tagesgrenze: sein Termin liegt um 18:00 UTC, wo
    // +/- eine Stunde auf keinen anderen Tag faellt.
    //
    // Mutation, die das faengt: in `eventsForDay` `add(deviceUtcOffset)` ->
    // `subtract(deviceUtcOffset)`. Sie ist heute in scheduling_v2_test,
    // _dst_test und _tz_test unsichtbar.

    const offset = Duration(hours: 2); // Juli, Europe/Berlin

    test('23:30 Ortszeit gehoert zum laufenden Tag', () {
      final result = hardFloor(
        day: DateTime.utc(2026, 7, 15),
        allEvents: [_meetingAt(DateTime.utc(2026, 7, 15, 21, 30))],
        deviceUtcOffset: offset,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );

      expect(result, DateTime.utc(2026, 7, 15, 21, 30));
    });

    test('00:30 Ortszeit gehoert zum FOLGETAG, nicht zum laufenden', () {
      final event = _meetingAt(DateTime.utc(2026, 7, 15, 22, 30));

      expect(
        hardFloor(
          day: DateTime.utc(2026, 7, 15),
          allEvents: [event],
          deviceUtcOffset: offset,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        ),
        isNull,
        reason: 'lokal 00:30 am 16.07. - nicht der 15.07.',
      );
      expect(
        hardFloor(
          day: DateTime.utc(2026, 7, 16),
          allEvents: [event],
          deviceUtcOffset: offset,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        ),
        DateTime.utc(2026, 7, 15, 22, 30),
      );
    });
  });

  group('FR-2: hardFloor darf vor Mitternacht des eigenen Tages liegen (T-118b)',
      () {
    // FR-2s Formel kennt keine Klammerung an den eigenen Tag:
    //
    //   hardFloor(Tag) = fruehester nicht-ganztaegiger Termin an diesem Tag
    //                    - durationToWakeUp - durationToGetReady
    //
    // Eine Klammerung waere genau der von FR-2 benannte Schadensfall ("ein
    // spaeterer Wert bedeutet, einen echten Termin zu verpassen"): bei einem
    // Termin um 00:30 wuerde erst um Mitternacht geweckt, also 30 Minuten vor
    // einem Termin, fuer den eine Stunde Vorlauf eingestellt ist.
    //
    // Mutation, die das faengt: das Ergebnis auf Mitternacht des eigenen Tages
    // klammern. Heute unsichtbar in scheduling_v2_test, _dst_test,
    // _audit_test und replan_test.
    //
    // Der Test haelt zugleich fest, dass Wert-Datum und Tagesschluessel
    // auseinanderfallen KOENNEN - die Voraussetzung jeder Entscheidung zu
    // T-120.

    test('Termin um 00:30 mit je 30min Vorlauf -> Weckwert am Vortag', () {
      final result = hardFloor(
        day: DateTime.utc(2026, 3, 12),
        allEvents: [_meetingAt(DateTime.utc(2026, 3, 12, 0, 30))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReady: const Duration(minutes: 30),
      );

      expect(result, DateTime.utc(2026, 3, 11, 23, 30));
      expect(result!.day, 11, reason: 'der Wert liegt auf dem VORTAG');
    });
  });

  group('FR-9: das Ventil loescht nie einen Tag, der etwas zu tun hat (T-118c)',
      () {
    // FR-9s "gestoppt" betrifft die FORTSCHREIBUNG. Zusammen mit FR-2
    // ("niemals spaeter … ein spaeterer Wert bedeutet, einen echten Termin zu
    // verpassen") und FR-5/FR-7 (auf einen kuenftigen realen Punkt ist ein Run
    // zu planen) ergibt das zwei Einschraenkungen, die beide heute in der
    // Ventilbedingung stehen und beide ungedeckt waren.
    //
    // Unsichtbar, weil jeder vorhandene Ventiltest mit LEEREM Kalender faehrt:
    // dort sind `ownHardFloor` immer null und `remaining` immer leer, die
    // beiden Teilbedingungen also nie falsch.
    //
    // Wogegen sie schuetzen: gegen jede Vereinfachung auf "Zaehler >= 7 ->
    // alles null" - die woertlichste Lesart von FR-9 und damit die
    // wahrscheinlichste Aufraeum-Aenderung. Ihr Wegfall waere ein stummer
    // Wecker an einem Tag mit echtem Termin.

    test('ein Tag mit eigenem Termin behaelt seinen Wert', () {
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 10),
        allEvents: [_meetingAt(_utc(8, 0, day: 11))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 42,
      );

      expect(result.valuesByDay[window[0]], isNotNull,
          reason: 'null hiesse, den Termin garantiert zu verpassen');
      // Der Wert ist 07:00, nicht 08:00 (docs/TODO.md T-132): ohne
      // `wunschzeit` haelt FR-4 bei der Uhrzeit des Ankers, und FR-2s
      // Obergrenze von 08:00 erlaubt jeden frueheren Wert ausdruecklich
      // ("immer erlaubt"). Bis 2026-09-11 stand hier 08:00 - das war der
      // Fehler, den eine Geraeterueckmeldung sichtbar gemacht hat: der
      // `hardFloor` wurde als Ziel behandelt statt als Deckel.
      expect(result.valuesByDay[window[0]], _utc(7, 0, day: 11));
    });

    test('Tage VOR einem Termin im Fenster behalten ihren Wert', () {
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 10),
        allEvents: [_meetingAt(_utc(6, 0, day: 15))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 42,
      );

      for (var i = 0; i < window.length; i++) {
        expect(result.valuesByDay[window[i]], isNotNull,
            reason: 'ein Run auf den Termin am letzten Fenstertag laeuft');
      }
    });

    test('ohne jeden Termin greift das Ventil weiterhin', () {
      // Gegenprobe gegen eine Ueberkorrektur.
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 10),
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 42,
      );

      expect(result.safetyValveTriggered, isTrue);
      expect(result.valuesByDay.values.every((v) => v == null), isTrue);
    });
  });

  group('FR-2/FR-3: ein gekappter Tag ist instant-verankert (T-118d)', () {
    // Wird ein Kurvenwert am eigenen `hardFloor` gekappt, kommt der Wert
    // danach unstrittig "direkt aus einem echten hardFloor" (FR-3) - er ist
    // also instant-verankert und darf bei einem Zeitzonenwechsel NICHT
    // ziffernweise mitwandern.
    //
    // Der Zweig war nie ausgefuehrt: die einzige positive Zusicherung zu
    // `instantAnchoredDays` in der Suite betrifft einen Tag, der seinen
    // hardFloor ueber den `remaining.isEmpty`-Zweig bekommt, und der einzige
    // Nachbartest prueft ausdruecklich den GEGENfall (die Kurve gewinnt, kein
    // Reset). Mutation: `if (clampedToOwnHardFloor) instantAnchoredDays.add(day);`
    // entfernen - heute unsichtbar in fuenf Testdateien.

    test('Kurvenwert ueber dem eigenen hardFloor wird gekappt und verankert',
        () {
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(9, 0, day: 10),
        allEvents: [
          _meetingAt(_utc(8, 0, day: 11)),
          _meetingAt(_utc(8, 30, day: 15)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 0,
      );

      expect(result.valuesByDay[window[0]], _utc(8, 0, day: 11),
          reason: 'FR-2s Obergrenze kappt den Kurvenwert');
      expect(result.instantAnchoredDays, contains(window[0]),
          reason: 'der gekappte Wert kommt aus einem echten hardFloor');
    });
  });

  group('Versaetze mit halben und dreiviertel Stunden (T-125)', () {
    // Saemtliche Versaetze der Suite waren bisher ganze Stunden
    // (`Duration.zero`, 1/2/5/9 h). Die Fehlerklasse "jemand rechnet mit
    // `offset.inHours` statt mit `offset`" ist damit in **keinem** Test
    // sichtbar - belegt ueber alle vierzehn Scheduling-Testdateien.
    //
    // Auch die CI-Zeitzonen-Matrix faengt sie nicht, obwohl sie St. John's,
    // Chatham und Lord Howe enthaelt: die Matrix setzt die Zone der
    // Testmaschine, waehrend die Domaenenschicht den Versatz als expliziten
    // Parameter bekommt (FR-2 "Testbarkeit"). Matrix und Unit-Test erfassen
    // also Verschiedenes und ersetzen einander nicht.

    test('Lord Howe: halbstuendige Umstellung, gleiche Ziffern in der neuen Zone',
        () {
      // +11:00 -> +10:30. Der Wert liest sich unter +11 als 05.04. 07:00;
      // gesucht ist der Instant, der unter +10:30 dieselben Ziffern ergibt.
      final result = reinterpretForNewOffset(
        value: DateTime.utc(2026, 4, 4, 20, 0),
        oldOffset: const Duration(hours: 11),
        newOffset: const Duration(hours: 10, minutes: 30),
      );

      expect(result, DateTime.utc(2026, 4, 4, 20, 30));
    });

    test('Chatham +12:45: der Drift landet auf einem anderen UTC-Datum', () {
      // Lokale Lesung 11:15Z + 12:45 = 11.03. 00:00; zu planen ist der
      // Folgetag, also lokal der 12.03.; Ziel 06:30, Abstand 6:30 > 30min ->
      // ein Schritt von 30min -> lokal 12.03. 00:30 -> Instant 11:45Z am 11.03.
      final result = applyGapDayDrift(
        v: DateTime.utc(2026, 3, 10, 11, 15),
        wunschzeit: const TimeOfDay(hour: 6, minute: 30),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: const Duration(hours: 12, minutes: 45),
      );

      expect(result, DateTime.utc(2026, 3, 11, 11, 45));
    });

    test('Chatham +12:45: Kaltstart legt den Wert auf den vorigen UTC-Tag', () {
      final result = coldStart(
        days: [DateTime.utc(2026, 4, 5)],
        wunschzeit: const TimeOfDay(hour: 0, minute: 15),
        deviceUtcOffset: const Duration(hours: 12, minutes: 45),
      );

      expect(result[DateTime.utc(2026, 4, 5)], DateTime.utc(2026, 4, 4, 11, 30));
    });
  });

  group('FR-2 als Invariante ueber eine volle Terminwoche (T-126)', () {
    // FR-2 ist eine Allaussage, kein Beispiel:
    //
    //   "`hardFloor` ist eine **Obergrenze** ('nicht spaeter als'). Der
    //    geplante Wert darf frueher liegen (immer erlaubt), aber **niemals
    //    spaeter** (ein spaeterer Wert bedeutet, einen echten Termin zu
    //    verpassen)."
    //
    // Deshalb ist sie hier als Invariante gepruft und nicht als Liste
    // handgerechneter Einzelwerte: eine solche Liste wird bei jeder legitimen
    // Kurvenaenderung ohnehin angepasst, die Invariante nicht. Belegt: FR-2s
    // Kappung laesst sich heute ersatzlos streichen, ohne dass ein einziger
    // bestehender Test rot wird.

    test('kein Tag wird spaeter geweckt als sein eigener hardFloor', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 11 + i));
      final events = [
        _meetingAt(_utc(9, 0, day: 11)),
        _meetingAt(_utc(8, 30, day: 12)),
        _meetingAt(_utc(12, 0, day: 13)),
        _meetingAt(_utc(6, 0, day: 14)),
        _meetingAt(_utc(10, 0, day: 15)),
        _meetingAt(_utc(5, 30, day: 16)),
        _meetingAt(_utc(9, 0, day: 17)),
      ];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(8, 0, day: 10),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      for (final day in window) {
        final value = result.valuesByDay[day];
        final floor = hardFloor(
          day: day,
          allEvents: events,
          deviceUtcOffset: Duration.zero,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        );
        expect(value, isNotNull,
            reason: 'jeder Tag hat einen echten Termin - keiner darf leer sein');
        expect(value!.isAfter(floor!), isFalse,
            reason: 'FR-2: niemals spaeter als der eigene hardFloor '
                '(${isoDate(day)}: Wert $value, Obergrenze $floor)');
      }
    });
  });

  group('FR-2: ein hardFloor zieht nur nach FRUEH, nie nach spaet (T-132)', () {
    // Geraeterueckmeldung vom 2026-09-11, echter Kalender: die Weckzeit lief
    // von 06:45 ueber 08:00 auf 11:00 - "deutlich mehr als drift und als
    // noetig, auch nicht nahe an der praeferierten zeit".
    //
    // FR-2 ist dazu eindeutig:
    //
    //   "`hardFloor` ist eine **Obergrenze** ("nicht spaeter als"). Der
    //    geplante Wert darf frueher liegen (IMMER ERLAUBT), aber niemals
    //    spaeter (ein spaeterer Wert bedeutet, einen echten Termin zu
    //    verpassen)."
    //
    // und FR-5 sagt denselben Satz noch einmal von der anderen Seite:
    //
    //   "`hardFloor` ist ausschliesslich eine Obergrenze (FR-2), NIE EINE
    //    RICHTUNGSVORGABE."
    //
    // Wer um 06:45 aufsteht, erfuellt einen Termin um 11:00 laengst. Es gibt
    // keinen Grund, dafuer auszuschlafen - und schon gar keinen, dafuer
    // `maxDailyDelta` zu reissen. Nach spaet bewegt die Weckzeit ausschliesslich
    // die `wunschzeit` (FR-4), begrenzt durch `maxDailyDelta`.

    test('zwei spaetere Termine ziehen die Weckzeit nicht hoch', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 12 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(6, 45, day: 11),
        allEvents: [
          _meetingAt(_utc(8, 0, day: 12)),
          _meetingAt(_utc(11, 0, day: 13)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      // FR-4: 06:45 -> 07:00 ist ein Schritt von 15min, innerhalb der Grenze,
      // und die wunschzeit wird exakt getroffen (kein Ueberschiessen).
      expect(result.valuesByDay[window[0]], _utc(7, 0, day: 12));
      // Danach halten - der 11-Uhr-Termin fordert nichts.
      expect(result.valuesByDay[window[1]], _utc(7, 0, day: 13));
      for (final day in window) {
        expect(result.valuesByDay[day], isNotNull);
        expect(result.valuesByDay[day]!.hour, lessThanOrEqualTo(7),
            reason: 'kein Tag darf ueber die wunschzeit hinaus nach hinten');
      }
    });

    test('ein einzelner spaeter Termin verbraucht nicht die freien Tage davor',
        () {
      // Der zweite Teil der Rueckmeldung ("reagiert extrem auf freie Tage"):
      // die Tage vor einem spaeten Termin wurden als Rampe benutzt, um auf ihn
      // hinaufzuklettern - 07:48, 08:52, 09:56, 11:00.
      final window = List.generate(7, (i) => _utc(0, 0, day: 12 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(6, 45, day: 11),
        allEvents: [_meetingAt(_utc(11, 0, day: 15))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      for (final day in window) {
        expect(result.valuesByDay[day], _utc(7, 0, day: day.day),
            reason: 'alle Tage ruhen auf der wunschzeit');
      }
    });

    test('nach FRUEH wird weiterhin geglaettet - unveraendert', () {
      // Gegenprobe, und der eigentliche Zweck von FR-5/FR-6: ein Termin, der
      // frueher liegt als die bisherige Weckzeit, ist bindend, und der Weg
      // dorthin wird ueber die Tage verteilt statt auf eine Nacht geworfen.
      final window = List.generate(7, (i) => _utc(0, 0, day: 12 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 11),
        allEvents: [_meetingAt(_utc(5, 0, day: 15))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 30, day: 12));
      expect(result.valuesByDay[window[1]], _utc(6, 0, day: 13));
      expect(result.valuesByDay[window[2]], _utc(5, 30, day: 14));
      expect(result.valuesByDay[window[3]], _utc(5, 0, day: 15));
    });
  });

  group('FR-6: auch die Kappung an einem Termin ist zu melden (T-133)', () {
    // FR-6: "Bei JEDER Ueberschreitung von `maxDailyDelta` (`N=1` oder
    // verteilt) wird der Nutzer einmalig benachrichtigt."
    //
    // T-105 hat das fuer den Zweig ohne Folgepunkte behoben. Der zweite Weg,
    // auf dem ein Tageswert an einem Termin gedeckelt wird - die Kappung eines
    // laufenden Kurvenwerts am eigenen `hardFloor` -, meldet weiterhin nichts.
    // Die urspruengliche Pruefung hatte ihn als schwaecheren Nebenbefund
    // notiert, weil die Meldung in ihrer Probe zufaellig trotzdem anfiel (ein
    // Folgetag startete einen neuen Run).
    //
    // Aufgefallen ist er an einem gerechneten Alltagsfall: die Weckzeit ist
    // ueber ein terminloses Wochenende bis zur `wunschzeit` gedriftet, danach
    // wird die Arbeit im Kalender nachgetragen. Der Montag wird auf seinen
    // `hardFloor` gedeckelt - ein Schritt von 45 Minuten bei erlaubten 30,
    // und der Nutzer erfaehrt nichts davon.

    test('ein Deckelungs-Sprung ueber maxDailyDelta wird gemeldet', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 14 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 13),
        allEvents: [
          _meetingAt(_utc(6, 15, day: 14)),
          _meetingAt(_utc(6, 15, day: 15)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 15, day: 14),
          reason: 'FR-2: der Termin deckelt den Wert - das ist richtig');
      expect(result.overrunNotificationNeeded, isTrue,
          reason: '45 Minuten bei erlaubten 30 - FR-6 fordert die Meldung');
    });

    test('eine Kappung innerhalb der Grenze meldet nicht', () {
      // Gegenprobe gegen eine Ueberkorrektur.
      final window = List.generate(7, (i) => _utc(0, 0, day: 14 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(6, 40, day: 13),
        allEvents: [
          _meetingAt(_utc(6, 15, day: 14)),
          _meetingAt(_utc(6, 15, day: 15)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 15, day: 14));
      expect(result.overrunNotificationNeeded, isFalse,
          reason: '25 Minuten liegen innerhalb der Grenze');
    });
  });
}
