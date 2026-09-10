import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// Phase 1 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge"): the pure
// segment/distribution core - distribute (FR-6), applyGapDayDrift (FR-4),
// hardFloor/eventsForDay (FR-2), groupTarget (FR-5), planGapOrRunStartDay (FR-7).
// Every test case here is taken verbatim (same numbers) from the "Test:" bullets
// under the matching FR in the spec.

DateTime _t(int hour, int minute, {int day = 1}) =>
    DateTime(2026, 1, day, hour, minute);

// FR-2 tests construct events directly in UTC and pass the device offset
// explicitly, so they're deterministic regardless of the host machine's own
// configured timezone (see spec, FR-2 "Testbarkeit").
DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 1, day, hour, minute);

Meeting _meetingAt(DateTime from, {bool isAllDay = false}) {
  return Meeting(
    from: from,
    to: from.add(const Duration(hours: 1)),
    isAllDay: isAllDay,
    startTimeZone: 'Etc/UTC',
    endTimeZone: 'Etc/UTC',
  );
}

void main() {
  group('distribute (FR-6)', () {
    test('Normalfall, Richtung "früher"', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(4, 30),
        n: 5,
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.overrunNotificationNeeded, isFalse);
      // Tag_i lands on anchor.day + i (a genuine calendar-date advance per
      // day) - only the wall-clock reading is interpolated; ΔT itself is
      // wall-clock-only (FR-6/FR-1, see distribute()'s doc comment).
      expect(result.valuesByDayOffset[1], _t(7, 18, day: 2));
      expect(result.valuesByDayOffset[2], _t(6, 36, day: 3));
      expect(result.valuesByDayOffset[3], _t(5, 54, day: 4));
      expect(result.valuesByDayOffset[4], _t(5, 12, day: 5));
      expect(result.valuesByDayOffset[5], _t(4, 30, day: 6));
    });

    test('Normalfall, Richtung "später"', () {
      final result = distribute(
        anchor: _t(6, 0),
        target: _t(9, 0),
        n: 3,
        maxDailyDelta: const Duration(minutes: 90),
      );

      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.valuesByDayOffset[1], _t(7, 0, day: 2));
      expect(result.valuesByDayOffset[2], _t(8, 0, day: 3));
      expect(result.valuesByDayOffset[3], _t(9, 0, day: 4));
    });

    test('erzwungener Bruch, N>1 - verteilt auf alle Tage, nicht gedumpt', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(4, 30),
        n: 3,
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.overrunNotificationNeeded, isTrue);
      expect(result.valuesByDayOffset[1], _t(6, 50, day: 2));
      expect(result.valuesByDayOffset[2], _t(5, 40, day: 3));
      expect(result.valuesByDayOffset[3], _t(4, 30, day: 4));
    });

    test('erzwungener Bruch, N=1 - voller Sprung ist kein Spezifikationsfehler', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(2, 0),
        n: 1,
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.overrunNotificationNeeded, isTrue);
      expect(result.valuesByDayOffset[1], _t(2, 0, day: 2));
    });
  });

  group('applyGapDayDrift (FR-4, isolated from FR-7s Deckel)', () {
    // Das Ergebnis liegt immer auf v.day + 1 (dem echten, tatsächlich
    // geplanten "heute") - genau wie distribute()s Tag_i-Platzierung, siehe
    // applyGapDayDrift()s Doc-Kommentar. Werte sind explizite UTC-Instants und
    // der Geräte-Versatz ist explizit 0 (T-61/Option B) - Verhalten bei
    // Versatz != 0 deckt test/scheduling_v2_offset_test.dart ab.
    test('kein wunschzeit -> hält (Uhrzeit unverändert, Datum +1)', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 0, day: 2));
    });

    test('Drift Richtung später, voller Schritt', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        wunschzeit: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 30, day: 2));
    });

    test('Drift Richtung früher, voller Schritt', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        wunschzeit: const TimeOfDay(hour: 5, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(6, 30, day: 2));
    });

    test('Ziel näher als maxDailyDelta -> kein Überschießen', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        wunschzeit: const TimeOfDay(hour: 7, minute: 15),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 15, day: 2));
    });

    test('wunschzeit bereits erreicht -> Uhrzeit unverändert, Datum +1', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        wunschzeit: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 0, day: 2));
    });
  });

  group('hardFloor / eventsForDay (FR-2)', () {
    test('mehrere Termine - der frühere zählt', () {
      final events = [
        _meetingAt(_utc(9, 0)),
        _meetingAt(_utc(7, 0)),
      ];

      final result = hardFloor(
        day: _utc(0, 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 15),
        durationToGetReady: const Duration(minutes: 15),
      );

      expect(result, _utc(6, 30));
    });

    test('ganztägiger Termin fließt nie ein', () {
      final events = [
        _meetingAt(_utc(12, 0), isAllDay: true),
        _meetingAt(_utc(8, 0)),
      ];

      final result = hardFloor(
        day: _utc(0, 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 15),
        durationToGetReady: const Duration(minutes: 15),
      );

      expect(result, _utc(7, 30));
    });

    test('nur ganztägig -> Lückentag, kein hardFloor', () {
      final events = [_meetingAt(_utc(12, 0), isAllDay: true)];

      final result = hardFloor(
        day: _utc(0, 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 15),
        durationToGetReady: const Duration(minutes: 15),
      );

      expect(result, isNull);
    });

    test('Termin-eigene Zeitzone: Tageszuordnung folgt der Geräte-Zeitzone', () {
      // Tom, Gerät in Europe/Berlin (CET, +1h). Termin startTimeZone=Asia/Tokyo,
      // Beginn 03:00 JST am "Tag 2" = bereits korrekt umgerechnet auf 18:00 UTC
      // am Vortag ("Tag 1") - diese Umrechnung ist vorhandene, unveränderte
      // Funktionalität und hier bereits als `from` gegeben, nicht Teil des Tests.
      final tokyoMeeting = _meetingAt(_utc(18, 0, day: 1));

      final berlinOffset = const Duration(hours: 1);

      final onVortag = eventsForDay(
        _utc(0, 0, day: 1),
        allEvents: [tokyoMeeting],
        deviceUtcOffset: berlinOffset,
      );
      expect(onVortag, [tokyoMeeting]);

      final onTokyoDatum = eventsForDay(
        _utc(0, 0, day: 2),
        allEvents: [tokyoMeeting],
        deviceUtcOffset: berlinOffset,
      );
      expect(onTokyoDatum, isEmpty);
    });
  });

  group('groupTarget (FR-5)', () {
    // Die Kurvenform hängt nicht von maxDailyDelta ab (nur die Overrun-Meldung
    // in distribute() tut das) - ein beliebiger Wert genügt hier.
    const maxDailyDelta = Duration(minutes: 60);

    // HardFloorPoint.value muss auf dem echten Kalendertag liegen, den sein
    // dayOffset behauptet (anchor.day + dayOffset) - genau wie computeWeekPlan
    // es später tatsächlich konstruiert; distribute()/groupTarget vergleichen
    // reale Daten, nicht nur Uhrzeiten (siehe distribute()s Datums-Fortschreibung).
    test('einfacher Fall - t1, t2 gleiche Richtung, keine Verletzung', () {
      final t1 = HardFloorPoint(dayOffset: 2, value: _t(7, 0, day: 3));
      final t2 = HardFloorPoint(dayOffset: 4, value: _t(6, 0, day: 5));

      final result = groupTarget(
        anchor: _t(8, 0, day: 1),
        points: [t1, t2],
        maxDailyDelta: maxDailyDelta,
      );

      expect(result, t2);
    });

    test('Zwischenpunkt würde verletzt - Run muss schrumpfen', () {
      final t1 = HardFloorPoint(dayOffset: 3, value: _t(6, 0, day: 4)); // Mittwoch, streng
      final t2 = HardFloorPoint(dayOffset: 5, value: _t(8, 0, day: 6)); // Freitag, lockerer

      final result = groupTarget(
        anchor: _t(9, 0, day: 1),
        points: [t1, t2],
        maxDailyDelta: maxDailyDelta,
      );

      expect(result, t1);
    });

    test('ΔT=0-Punkt beendet seinen Run sofort bei sich selbst', () {
      final t1 = HardFloorPoint(dayOffset: 2, value: _t(7, 0, day: 3)); // ΔT=0
      final t2 = HardFloorPoint(dayOffset: 5, value: _t(9, 0, day: 6));

      final result = groupTarget(
        anchor: _t(7, 0, day: 1),
        points: [t1, t2],
        maxDailyDelta: maxDailyDelta,
      );

      expect(result, t1);
    });
  });

  group('planGapOrRunStartDay (FR-7)', () {
    // HardFloorPoint.dayOffset is always relative to "today" (the `v` passed
    // in for THIS call) - each simulated day below is its own fresh call,
    // exactly as a real daily replanning loop would rebase it.

    test('ein hardFloor-Punkt: Montag driftet, Dienstag startet den Run', () {
      const wunschzeit = TimeOfDay(hour: 10, minute: 0);
      const maxDailyDelta = Duration(minutes: 30);
      final f = _utc(5, 0); // Samstag, 05:00

      // remainingPoints' dayOffset ist v-relativ (die echte Kalendertage-Distanz
      // von v zu F) - das braucht groupTarget/distribute zwingend so für die
      // Datumsplatzierung (siehe groupTarget-Tests). v ist "Sonntag" (Tag 1);
      // F=Samstag ist 6 Tage davon entfernt (Mo,Di,Mi,Do,Fr,Sa). planGapOrRunStartDay
      // zieht davon selbst 1 ab, um das spec-eigene N_Rest ("Tage von morgen bis
      // F, F eingeschlossen" = 5 für Montag) zu bilden.
      final montag = planGapOrRunStartDay(
        v: _utc(7, 0),
        remainingPoints: [HardFloorPoint(dayOffset: 6, value: f)],
        wunschzeit: wunschzeit,
        maxDailyDelta: maxDailyDelta,
        deviceUtcOffset: Duration.zero,
      );
      // v ist der Anker "gestern" (Sonntag); planGapOrRunStartDay berechnet
      // stets den Wert für den echten Folgetag (siehe applyGapDayDrift()s
      // Datums-Fortschreibung) - "Montag" landet also auf v.day + 1.
      expect(montag.value, _utc(7, 30, day: 2));
      expect(montag.overrunNotificationNeeded, isFalse);

      // Dienstag: Anker ist jetzt Montags tatsächliches Ergebnis (Tag 2); F ist
      // von dort noch 5 Tage entfernt (Mi,Do,Fr,Sa + F selbst).
      final dienstag = planGapOrRunStartDay(
        v: montag.value,
        remainingPoints: [HardFloorPoint(dayOffset: 5, value: f)],
        wunschzeit: wunschzeit,
        maxDailyDelta: maxDailyDelta,
        deviceUtcOffset: Duration.zero,
      );
      expect(dienstag.value, _utc(7, 0, day: 3));
      expect(dienstag.overrunNotificationNeeded, isFalse);
    });

    test('zwei hardFloor-Punkte, FR-5-Ziel ≠ nächster Punkt: Montag startet sofort', () {
      const maxDailyDelta = Duration(minutes: 30);
      // v (Sonntag, Anker) ist Tag 1; die Werte müssen auf v.day + dayOffset
      // liegen, damit groupTargets Zwischenpunkt-Prüfung reale Daten vergleicht
      // (siehe groupTarget-Tests oben). Freitag ist 5 Tage nach Sonntag (Tag 6),
      // Samstag 6 Tage (Tag 7).
      final t1 = _utc(6, 0, day: 6); // Freitag, locker
      final t2 = _utc(4, 0, day: 7); // Samstag, streng

      // Montag: t1 (Freitag) ist 5 Tage von v entfernt, t2 (Samstag) 6 Tage.
      final montag = planGapOrRunStartDay(
        v: _utc(7, 0),
        remainingPoints: [
          HardFloorPoint(dayOffset: 5, value: t1),
          HardFloorPoint(dayOffset: 6, value: t2),
        ],
        wunschzeit: null,
        maxDailyDelta: maxDailyDelta,
        deviceUtcOffset: Duration.zero,
      );

      expect(montag.value, _utc(6, 30, day: 2));
      expect(montag.overrunNotificationNeeded, isFalse);
    });
  });

  group('updateGapDayCounter (FR-9)', () {
    test('Tag mit realem hardFloor setzt zurück', () {
      expect(
        updateGapDayCounter(previousCounter: 6, dayHadRealHardFloor: true),
        0,
      );
    });

    test('Tag ohne hardFloor erhöht um 1', () {
      expect(
        updateGapDayCounter(previousCounter: 6, dayHadRealHardFloor: false),
        7,
      );
    });

    test('rollierend über mehrere Tage - 6 termin-lose Tage vor heute', () {
      var counter = 0;
      for (var i = 0; i < 6; i++) {
        counter = updateGapDayCounter(
          previousCounter: counter,
          dayHadRealHardFloor: false,
        );
      }
      expect(counter, 6); // noch nicht 7 -> kein Auslösen
    });
  });

  group('coldStart (FR-10)', () {
    test('Tag1-5 termin-los, keine wunschzeit -> kein Alarm geplant', () {
      final days = [
        _utc(0, 0, day: 1),
        _utc(0, 0, day: 2),
        _utc(0, 0, day: 3),
        _utc(0, 0, day: 4),
        _utc(0, 0, day: 5),
      ];

      final result = coldStart(
          days: days, wunschzeit: null, deviceUtcOffset: Duration.zero);

      expect(result.length, 5);
      expect(result.values.every((v) => v == null), isTrue);
    });

    test('mit wunschzeit -> diese Tage nutzen sie', () {
      final days = [_utc(0, 0, day: 1), _utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        wunschzeit: const TimeOfDay(hour: 9, minute: 0),
        deviceUtcOffset: Duration.zero,
      );

      expect(result[days[0]], _utc(9, 0, day: 1));
      expect(result[days[1]], _utc(9, 0, day: 2));
    });
  });

  group('computeWeekPlan (FR-8)', () {
    DateTime day(int n) => _utc(0, 0, day: n);

    test('Kaltstart: Tag1-5 termin-los, Tag6 hardFloor=05:30, keine wunschzeit', () {
      final window = [1, 2, 3, 4, 5, 6].map(day).toList();
      final events = [_meetingAt(_utc(5, 30, day: 6))];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      for (var d = 1; d <= 5; d++) {
        expect(result.valuesByDay[day(d)], isNull);
      }
      expect(result.valuesByDay[day(6)], _utc(5, 30, day: 6));
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);
    });

    test('ein hardFloor-Punkt am Fensterende - komplette Woche durchgerechnet '
        '(Regressionstest: Freitag war vor dem N_Rest<=1-Fix falsch)', () {
      final window = [1, 2, 3, 4, 5, 6].map(day).toList(); // Mo..Sa
      final events = [_meetingAt(_utc(5, 0, day: 6))]; // Sa, F=05:00

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0), // So, Anker
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 10, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
      );

      // Montag (i=1, N_F=6, N_Rest=5): Halten erfüllt 24min<=30min, voller
      // Drift (30min<=30min, Grenze) -> 07:30 (deckt sich exakt mit FR-7s
      // eigenem durchgerechneten Testfall oben, "ein hardFloor-Punkt: Montag
      // driftet").
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1)); // Mo
      // Dienstag (i=2, N_Rest=4): Halten bei 07:30 verletzt 37,5min>30min ->
      // Tag 1 eines neuen Runs, N=5 (Di-Sa): Di=07:00, Mi=06:30, Do=06:00,
      // Fr=05:30, Sa=05:00 - identisch mit FR-7s eigenem Testfall.
      expect(result.valuesByDay[day(2)], _utc(7, 0, day: 2)); // Di
      expect(result.valuesByDay[day(3)], _utc(6, 30, day: 3)); // Mi
      expect(result.valuesByDay[day(4)], _utc(6, 0, day: 4)); // Do
      expect(result.valuesByDay[day(5)], _utc(5, 30, day: 5)); // Fr
      expect(result.valuesByDay[day(6)], _utc(5, 0, day: 6)); // Sa, eigener hardFloor
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);
    });

    test('zwei hardFloor-Punkte: loser Zwischentermin wird glatt unterschritten, '
        'nicht auf seinen eigenen hardFloor zurückgesetzt', () {
      final window = [1, 2, 3, 4].map(day).toList(); // Mo..Do
      final events = [
        _meetingAt(_utc(8, 0, day: 3)), // Mi, locker
        _meetingAt(_utc(3, 0, day: 4)), // Do, streng
      ];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(9, 0, day: 0), // So, Anker
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: null,
        maxDailyDelta: const Duration(minutes: 90),
        gapDayCounter: 0,
      );

      // FR-5 (hypothetisch, A=So 09:00): t_m=Do 03:00 (streng), N_F=4 (Verteilung
      // A->Do über 4 Tage ergibt an Mi 04:30, verletzt Mis eigenen hardFloor
      // 08:00 nicht). Montag (i=1, N_Rest=3): Halten bei 09:00 verletzt bereits
      // 120min>90min -> Montag ist selbst Tag 1 des Runs, N=4: Mo=07:30.
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1)); // Mo
      // Dienstag (i=2 ab dem neuen Anker Mo=07:30, N_Rest=2 bis Do): Halten
      // verletzt 135min>90min -> Tag 1 eines neuen Runs, N=3: Di=06:00.
      expect(result.valuesByDay[day(2)], _utc(6, 0, day: 2)); // Di
      // Mi: eigener hardFloor wäre 08:00, aber die Kurve (04:30) unterschreitet
      // ihn ohne ihn zu verletzen - die Kurve gewinnt, kein Reset auf 08:00.
      expect(result.valuesByDay[day(3)], _utc(4, 30, day: 3));
      expect(result.valuesByDay[day(4)], _utc(3, 0, day: 4)); // Do, eigener hardFloor
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);

      // FR-16 braucht pro Tag die Information, ob der Wert instant-verankert
      // ist (direkt aus einem echten hardFloor - der Termin verschiebt sich
      // bei einem Zeitzonenwechsel nicht) oder ziffern-verankert (aus
      // wunschzeit/Kurve - da gilt die Alarmuhren-Konvention). Genau dieses
      // Szenario unterscheidet beides: Mi liegt auf der Kurve (04:30), obwohl
      // der Tag einen eigenen hardFloor (08:00) hat, Do dagegen exakt auf
      // seinem hardFloor.
      expect(result.instantAnchoredDays, {day(4)});
    });

    // FR-9s Ventil greift laut Spec nur ohne gesetzte `wunschzeit`
    // (Ausnahme nachträglich ergänzt, docs/TODO.md T-78) - dieser Fall setzt
    // deshalb bewusst keine.
    test(
        'Sicherheitsventil: Zähler bereits bei 7, kein hardFloor im Fenster, keine wunschzeit',
        () {
      final window = [1, 2, 3].map(day).toList();

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

      expect(result.valuesByDay.values.every((v) => v == null), isTrue);
      expect(result.safetyValveTriggered, isTrue);
    });

    // docs/TODO.md T-78 / FR-9 "Ausnahme: gesetzte wunschzeit": das Ventil
    // schützt gegen blinde Fortschreibung. Mit einer wunschzeit ist die
    // Fortschreibung durch FR-4 beschränkt (sie hält exakt auf der wunschzeit
    // an), es gibt also nichts, wovor zu schützen wäre - und das Auslösen wäre
    // hier eine Einbahnstraße: ohne Alarme gibt es keinen Ring-Checkpoint mehr,
    // der den Zähler je zurücksetzen könnte.
    test('Sicherheitsventil greift NICHT, wenn eine wunschzeit gesetzt ist', () {
      final window = [1, 2, 3].map(day).toList();

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
        wunschzeit: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 42, // weit jenseits der Schwelle
      );

      expect(result.safetyValveTriggered, isFalse);
      expect(result.valuesByDay.length, 3);
      expect(result.valuesByDay.values.every((v) => v != null), isTrue,
          reason: 'jeder Fenstertag behält einen Wert, '
              'bekommen ${result.valuesByDay}');
      // FR-4 driftet weiter Richtung 09:00, in 30-Minuten-Schritten.
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1));
      expect(result.valuesByDay[day(3)], _utc(8, 30, day: 3));
    });
  });

  // Phase 3 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge"):
  // reinterpretForNewOffset (FR-16) - unabhängig von Phase 1/2, braucht nur
  // Phase 0. Beide Testfälle sind wörtlich die spec-eigenen "Test:"-Bullets
  // unter FR-16.
  group('reinterpretForNewOffset (FR-16)', () {
    test('Ortswechsel: 09:00 in Zone A (+1) bleibt 09:00, jetzt in Zone B (+9)', () {
      // 09:00 lokal unter +1 = 08:00 UTC.
      final result = reinterpretForNewOffset(
        value: _utc(8, 0),
        oldOffset: const Duration(hours: 1),
        newOffset: const Duration(hours: 9),
      );

      // 09:00 lokal unter +9 = 00:00 UTC - gleiche Ziffern, neue Zone.
      expect(result, _utc(0, 0));
    });

    test('Sommerzeit: 07:00 unter MEZ (+1) bleibt 07:00 unter MESZ (+2)', () {
      // 07:00 lokal unter +1 = 06:00 UTC.
      final result = reinterpretForNewOffset(
        value: _utc(6, 0),
        oldOffset: const Duration(hours: 1),
        newOffset: const Duration(hours: 2),
      );

      // 07:00 lokal unter +2 = 05:00 UTC.
      expect(result, _utc(5, 0));
    });
  });
}
