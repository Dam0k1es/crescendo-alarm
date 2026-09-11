import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// Regressionen aus der unabhaengigen Spec-Pruefung (2026-09-11), Ebene
// replan()/Zustandsbuchfuehrung. Die Domaenen-Gegenstuecke liegen in
// test/scheduling_v2_audit_test.dart.
//
// Jeder Fall nennt die Kennung, unter der er in docs/TODO.md gefuehrt wird.

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
  group('FR-11: der geklingelte Tageswert ist fix, auch heute noch (T-106)', () {
    // FR-11:
    //
    //   "Ein bereits berechneter, aber noch nicht ausgeloester Tageswert bleibt
    //    revisionierbar [...] Erst der tatsaechlich ausgeloeste Wert ist fuer
    //    immer fix."
    //
    // "Fuer immer" schliesst den Rest desselben Tages ein. Nur der
    // Ring-Checkpoint setzt `todayAlreadyRang`; fuer jeden anderen Ausloeser
    // beginnt das Fenster deshalb wieder bei HEUTE, und der Merge schrieb den
    // bereits geklingelten Wert ueberschreibungsfrei neu.
    //
    // FR-17s Tagessperre faengt `appForeground` ab - dort hat der Ring
    // `lastReplanDate` schon auf heute gesetzt. `settingsChanged` und
    // `manualSync` unterliegen ihr bewusst nicht und tragen den Fall allein:
    // Ton- und Lautstaerkeregler, die vier Dauer-Picker, der
    // wunschzeit-Schalter, der Gentle-Wake-Schalter und der Sync-Knopf.

    test('ein Nicht-Ring-Replan am selben Tag laesst den geklingelten Wert stehen',
        () async {
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      final rangAt = _utc(6, 0, day: 10);

      // Vorgeschichte: gestern 09:00, heute um 06:00 geklingelt (ein Termin
      // um 06:00 hatte den Wert erzwungen).
      appState.pendingDayValues = {
        isoDate(dayMarker(ringDay, -1)): _utc(9, 0, day: 9).millisecondsSinceEpoch,
        isoDate(ringDay): rangAt.millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = ringDay;
      appState.lastReplanDate = ringDay;
      appState.wunschzeit = const TimeOfDay(hour: 9, minute: 0);

      // 08:00: der Termin ist abgesagt, der Nutzer aendert eine Einstellung.
      await replan(
        appState,
        now: () => _utc(8, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        // settingsChanged/manualSync: heute gilt NICHT als abgeschlossen
        todayAlreadyRang: false,
      );

      expect(
        appState.pendingDayValues[isoDate(ringDay)],
        rangAt.millisecondsSinceEpoch,
        reason: 'FR-11: der ausgeloeste Wert ist fix, auch fuer den Rest des Tages',
      );
    });

    test('der Folgetag bleibt dabei sehr wohl revisionierbar', () async {
      // Gegenprobe gegen eine Ueberkorrektur: FR-11s erste Haelfte
      // ("noch nicht ausgeloest -> revisionierbar") muss erhalten bleiben.
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);
      final nextDay = dayMarker(ringDay, 1);

      appState.pendingDayValues = {
        isoDate(ringDay): _utc(6, 0, day: 10).millisecondsSinceEpoch,
        isoDate(nextDay): _utc(6, 0, day: 11).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = ringDay;
      appState.lastReplanDate = ringDay;
      appState.wunschzeit = const TimeOfDay(hour: 9, minute: 0);
      appState.maxDailyDelta = const Duration(minutes: 30);

      await replan(
        appState,
        now: () => _utc(8, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [],
        todayAlreadyRang: false,
      );

      expect(
        appState.pendingDayValues[isoDate(nextDay)],
        isNot(_utc(6, 0, day: 11).millisecondsSinceEpoch),
        reason: 'der Folgetag hat nicht geklingelt und driftet zur wunschzeit',
      );
    });

    test('der Ring-Checkpoint selbst schreibt den heutigen Wert weiterhin',
        () async {
      // Zweite Gegenprobe: die Sperre darf nur fuer bereits abgeschlossene
      // Tage gelten, nicht fuer den Ring, der sie ueberhaupt erst abschliesst.
      final appState = await _freshAppState();
      final ringDay = _utc(0, 0, day: 10);

      appState.pendingDayValues = {
        isoDate(dayMarker(ringDay, -1)): _utc(7, 0, day: 9).millisecondsSinceEpoch,
      };
      appState.lastProcessedConcludedDay = dayMarker(ringDay, -1);
      appState.wunschzeit = const TimeOfDay(hour: 7, minute: 0);

      await replan(
        appState,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [_meetingAt(_utc(5, 0, day: 11))],
        todayAlreadyRang: true,
      );

      expect(appState.pendingDayValues[isoDate(dayMarker(ringDay, 1))], isNotNull,
          reason: 'das Fenster des Ring-Pfads beginnt morgen und wird geschrieben');
    });
  });
}
