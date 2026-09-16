import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-76: computeWeekPlan leitete die dayOffsets seiner
// HardFloorPoints über `window[j].difference(anchorDay).inDays` ab. Auf lokal
// getaggten Fenstermarkern zählt das über eine Sommerzeit-Umstellung um einen
// Tag zu wenig - zwei Fenstertage bekommen denselben Offset. Folge: N_Rest zu
// klein, die Kurve zu steil, und `groupTarget`s Verletzungsprüfung vergleicht
// den falschen Tag gegen seinen hardFloor.
//
// Warum `tz.TZDateTime` als Fenstermarker: in Produktion baut replan() das
// Fenster aus lokal getaggten Mitternachtsmarkern; auf der
// Entwicklungsmaschine (UTC+0) verhalten die sich aber wie UTC und der Fehler
// bleibt unsichtbar. `tz.TZDateTime` ist ein `DateTime` mit echtem
// Umstellungsverhalten und macht den Test unabhängig von der Zeitzone der
// Testmaschine - genau die Lücke, an der der erste Fix (T-74d) vorbeilief.

const cest = Duration(hours: 2);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('T-76: die Kurve nutzt die echte Kalender-Tagesdistanz über die Umstellung',
      () {
    final berlin = tz.getLocation('Europe/Berlin');
    // Fenster 2026-03-28 .. 2026-04-03; die Umstellung liegt am 2026-03-29.
    final window =
        List.generate(7, (i) => tz.TZDateTime(berlin, 2026, 3, 28 + i));

    // Der Anker gehört konzeptionell zum 2026-03-27 (dem Tag vor dem Fenster):
    // 05:00 UTC = 07:00 Berlin.
    final anchor = DateTime.utc(2026, 3, 27, 5, 0);

    // Ein einziger echter Termin, am letzten Fenstertag: 05:10 UTC = 07:10
    // Berlin am 2026-04-03. Mit 30min Aufstehen + 2h Fertigwerden ergibt das
    // einen hardFloor von 02:40 UTC = 04:40 Berlin, also ΔT = -140 min
    // gegenüber dem Anker.
    final event = Meeting(
      from: tz.TZDateTime.from(DateTime.utc(2026, 4, 3, 5, 10), berlin),
      to: tz.TZDateTime.from(DateTime.utc(2026, 4, 3, 6, 10), berlin),
      isAllDay: false,
      startTimeZone: 'Europe/Berlin',
      endTimeZone: 'Europe/Berlin',
    );

    final result = computeWeekPlan(
      window: window,
      lastEffectiveWakeTime: anchor,
      allEvents: [event],
      deviceUtcOffset: cest,
      durationToWakeUp: const Duration(minutes: 30),
      durationToGetReady: const Duration(hours: 2),
      preferredWakeUpTime: null,
      maxDailyDelta: const Duration(minutes: 20),
      gapDayCounter: 0,
    );

    // Vom Anker (27.03.) zum Ziel (03.04.) sind es 7 Kalendertage. Das bloße
    // Halten ist infeasible (140/6 = 23,3 min > 20 min), heute ist also Tag 1
    // eines 7-Tage-Runs: der Schritt ist 140/7 = genau 20 min.
    // Mit dem Fehler wurde der Zielabstand als 6 Tage gezählt -> N = 6 ->
    // Schritt 23,33 min -> 06:36:40 statt 06:40.
    expect(
      result.valuesByDay[window[0]],
      DateTime.utc(2026, 3, 28, 4, 40),
      reason: 'erwartet 04:40 UTC (= 06:40 Berlin, Schritt genau 20 min), '
          'bekommen ${result.valuesByDay[window[0]]}',
    );

    // Und der Termin selbst wird exakt getroffen, nicht überschritten (FR-2).
    expect(result.valuesByDay[window[6]], DateTime.utc(2026, 4, 3, 2, 40));

    // Jeder Fenstertag bekommt genau einen eigenen Wert - kein Tag fällt durch
    // eine Offset-Kollision aus dem Plan.
    expect(result.valuesByDay.length, 7);
    expect(window.map(isoDate).toSet().length, 7);
  });

  test('T-76: ein Kaltstart über die Umstellung verankert auf dem richtigen Tag',
      () {
    final berlin = tz.getLocation('Europe/Berlin');
    final window =
        List.generate(7, (i) => tz.TZDateTime(berlin, 2026, 3, 28 + i));

    // Erster echter Termin am 2026-03-31 (also nach der Umstellung), damit der
    // Kaltstart-Zweig seinen Anker mitten im Fenster setzt und die
    // dayOffsets danach über die Umstellung hinweg gezählt werden.
    Meeting at(int day, int utcHour, int utcMinute) => Meeting(
          from: tz.TZDateTime.from(
              DateTime.utc(2026, 3, day, utcHour, utcMinute), berlin),
          to: tz.TZDateTime.from(
              DateTime.utc(2026, 3, day, utcHour + 1, utcMinute), berlin),
          isAllDay: false,
          startTimeZone: 'Europe/Berlin',
          endTimeZone: 'Europe/Berlin',
        );

    final result = computeWeekPlan(
      window: window,
      lastEffectiveWakeTime: null,
      allEvents: [at(31, 6, 0), at(2, 6, 0)],
      deviceUtcOffset: cest,
      durationToWakeUp: const Duration(minutes: 30),
      durationToGetReady: Duration.zero,
      preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
      maxDailyDelta: const Duration(minutes: 30),
      gapDayCounter: 0,
    );

    // Der Ankertag (31.03.) trägt den hardFloor selbst und ist
    // instant-verankert; alle sieben Tage müssen einen Wert haben.
    expect(result.valuesByDay[window[3]], DateTime.utc(2026, 3, 31, 5, 30));
    expect(result.instantAnchoredDays.contains(window[3]), isTrue);
    expect(result.valuesByDay.length, 7);
  });
}
