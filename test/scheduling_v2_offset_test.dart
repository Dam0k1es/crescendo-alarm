import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-61, Ebene 1/2/3 der geplanten Teststruktur.
//
// Semantik (Option B, entschieden vor diesen Tests): jeder Wert der
// Domänenschicht ist ein **echter absoluter Instant** (FR-1). Nur dort, wo
// eine geräte-lokale `TimeOfDay` (`preferredWakeUpTime`) auf einen Instant trifft, muss
// `deviceUtcOffset` einfließen - also in applyGapDayDrift und coldStart.
// distribute/groupTarget sind dagegen frame-invariant: sie vergleichen
// ausschließlich Instant mit Instant, und die Tag_i-Platzierung im lokalen
// Frame ergibt nach Rückumrechnung exakt denselben Instant wie im Rohframe.
//
// Alle Instants werden explizit als UTC konstruiert und der Geräte-Versatz
// explizit übergeben - die Systemzeitzone der Testmaschine darf nie einfließen
// (FR-2 "Testbarkeit").

/// Ein echter Instant (UTC).
DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 3, day, hour, minute);

/// Gerät in Berlin-Sommerzeit.
const berlin = Duration(hours: 2);

void main() {
  group('applyGapDayDrift mit deviceUtcOffset != 0 (T-61, Ebene 2)', () {
    test('wunschzeit ist bereits erreicht (lokal gelesen) -> kein Drift', () {
      // v = 05:00 UTC = 07:00 lokal in Berlin. preferredWakeUpTime ist 07:00 lokal,
      // also genau erreicht - es darf NICHT gedriftet werden. Der alte Code
      // liest 05:00 als Ziffern und driftet 30min Richtung "07:00".
      final result = applyGapDayDrift(
        v: _utc(5, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: berlin,
      );

      expect(result, _utc(5, 0, day: 2));
    });

    test('Drift Richtung später wird lokal gemessen', () {
      // v = 05:00 UTC = 07:00 lokal, preferredWakeUpTime 09:00 lokal -> Distanz 2h,
      // gekappt auf 30min -> 07:30 lokal = 05:30 UTC am Folgetag.
      final result = applyGapDayDrift(
        v: _utc(5, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: berlin,
      );

      expect(result, _utc(5, 30, day: 2));
    });

    test('lokales Datum zählt, nicht das UTC-Datum', () {
      // v = 23:00 UTC am Tag 1 = 01:00 lokal am Tag 2. "Morgen" ist damit
      // lokal Tag 3, nicht Tag 2. preferredWakeUpTime = 01:00 lokal (erreicht).
      final result = applyGapDayDrift(
        v: _utc(23, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 1, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: berlin,
      );

      // lokal Tag 3, 01:00 -> Instant 23:00 UTC am Tag 2.
      expect(result, _utc(23, 0, day: 2));
    });

    test('Invarianz: bei deviceUtcOffset = 0 unverändertes Verhalten', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );

      expect(result, _utc(7, 30, day: 2));
    });
  });

  group('coldStart mit deviceUtcOffset != 0 (T-61, Ebene 2)', () {
    test('wunschzeit wird als lokale Uhrzeit des Fenstertages gesetzt', () {
      // Fenstertage sind lokale Kalenderdaten (Datums-Marker). preferredWakeUpTime
      // 07:00 lokal am Tag 1 -> Instant 05:00 UTC am Tag 1.
      final days = [_utc(0, 0, day: 1), _utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        deviceUtcOffset: berlin,
      );

      expect(result[days[0]], _utc(5, 0, day: 1));
      expect(result[days[1]], _utc(5, 0, day: 2));
    });

    test('lokale Uhrzeit vor dem Versatz rutscht auf den UTC-Vortag', () {
      // 01:00 lokal am Tag 2 = 23:00 UTC am Tag 1.
      final days = [_utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 1, minute: 0),
        deviceUtcOffset: berlin,
      );

      expect(result[days[0]], _utc(23, 0, day: 1));
    });

    test('Invarianz: bei deviceUtcOffset = 0 unverändertes Verhalten', () {
      final days = [_utc(0, 0, day: 1)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        deviceUtcOffset: Duration.zero,
      );

      expect(result[days[0]], _utc(9, 0, day: 1));
    });
  });

  group('hardFloor unter Versatz (T-61, Ebene 1)', () {
    Meeting meetingAt(DateTime from) => Meeting(
          from: from,
          to: from.add(const Duration(hours: 1)),
          isAllDay: false,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        );

    test('der Rückgabewert ist versatz-unabhängig (der Termin verschiebt sich nicht)',
        () {
      // 23:00 UTC am Tag 10 = 01:00 lokal am Tag 11 (Berlin, +2).
      final event = meetingAt(_utc(23, 0, day: 10));

      final berlinValue = hardFloor(
        day: _utc(0, 0, day: 11), // lokaler Kalendertag in Berlin
        allEvents: [event],
        deviceUtcOffset: berlin,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );
      final utcValue = hardFloor(
        day: _utc(0, 0, day: 10), // derselbe Termin, aber UTC-Kalendertag
        allEvents: [event],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );

      // FR-1/FR-16: instant-basiert - identischer Instant in beiden Zonen.
      expect(berlinValue, _utc(23, 0, day: 10));
      expect(utcValue, berlinValue);
    });

    test('die Tageszuordnung dagegen folgt dem Versatz', () {
      final event = meetingAt(_utc(23, 0, day: 10));

      // Unter +2 gehört der Termin zum lokalen Tag 11, nicht zum Tag 10.
      expect(
        hardFloor(
          day: _utc(0, 0, day: 10),
          allEvents: [event],
          deviceUtcOffset: berlin,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        ),
        isNull,
      );
    });
  });

  group('computeWeekPlan-Invarianz (T-61, Ebene 3a)', () {
    Meeting meetingAt(DateTime from) => Meeting(
          from: from,
          to: from.add(const Duration(hours: 1)),
          isAllDay: false,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        );

    test('gleiche lokale Termin-Ablesung -> gleicher Plan, nur um den Versatz verschoben',
        () {
      final window = [1, 2, 3, 4, 5, 6].map((d) => _utc(0, 0, day: d)).toList();

      WeekPlanResult plan(Duration offset, Duration eventShift) => computeWeekPlan(
            window: window,
            lastEffectiveWakeTime: _utc(7, 0, day: 0).subtract(offset),
            // Termin so verschoben, dass seine LOKALE Ablesung in beiden
            // Läufen identisch ist (05:00 lokal am Tag 6).
            allEvents: [meetingAt(_utc(5, 0, day: 6).subtract(eventShift))],
            deviceUtcOffset: offset,
            durationToWakeUp: Duration.zero,
            durationToGetReady: Duration.zero,
            preferredWakeUpTime: const TimeOfDay(hour: 10, minute: 0),
            maxDailyDelta: const Duration(minutes: 30),
            gapDayCounter: 0,
          );

      final atUtc = plan(Duration.zero, Duration.zero);
      final atBerlin = plan(berlin, berlin);

      for (final day in window) {
        final utcValue = atUtc.valuesByDay[day];
        final berlinValue = atBerlin.valuesByDay[day];
        if (utcValue == null) {
          expect(berlinValue, isNull, reason: 'Tag $day');
          continue;
        }
        // Identische lokale Ziffern => Instants differieren genau um den
        // Versatz. Wäre die Arithmetik frame-inkonsistent, würde hier etwas
        // anderes herauskommen.
        expect(berlinValue, utcValue.subtract(berlin), reason: 'Tag $day');
      }
    });
  });

  group('distribute/groupTarget sind frame-invariant (T-61, festgeschrieben)', () {
    test('distribute liefert bei jedem Versatz denselben Instant', () {
      final anchor = _utc(5, 0, day: 1);
      final target = _utc(3, 0, day: 3);

      final zero = distribute(
        anchor: anchor,
        target: target,
        n: 2,
        maxDailyDelta: const Duration(hours: 2),
      );
      final shifted = distribute(
        anchor: anchor,
        target: target,
        n: 2,
        maxDailyDelta: const Duration(hours: 2),
      );

      // Bewusst dieselbe Signatur: distribute bekommt KEINEN Versatz, weil er
      // das Ergebnis nicht verändern kann (Differenz zweier Instants im
      // gleichen Frame, und die Tag_i-Platzierung ist offsetneutral).
      expect(shifted.valuesByDayOffset[1], zero.valuesByDayOffset[1]);
      expect(shifted.valuesByDayOffset[2], zero.valuesByDayOffset[2]);
      expect(zero.valuesByDayOffset[2], _utc(3, 0, day: 3));
    });
  });
}
