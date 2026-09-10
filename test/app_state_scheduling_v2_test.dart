import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';

// Phase 0, Schritt 2 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge"):
// Persistenz-Rundreise für die vier neuen Scheduling-v2-Felder (FR-3), nach
// demselben Muster wie die bestehenden AppState-Felder (int -> setInt/getInt,
// String-kodiert für alles andere). pendingDayValues wird zusätzlich direkt
// über eine frische SharedPreferences-Instanz zurückgelesen (nicht über
// AppState) - das simuliert genau den Zugriff, den der Hintergrund-Isolate
// aus FR-16 später braucht (siehe Architektur, "Reale Anbindung" Fund 1).

void main() {
  group('Scheduling-v2 AppState-Felder (FR-3) - Persistenz-Rundreise', () {
    test('gapDayCounter (FR-9)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      first.gapDayCounter = 5;

      final second = AppState();
      await second.initialized;
      expect(second.gapDayCounter, 5);
    });

    test('lastCheckedUtcOffset (FR-16)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      first.lastCheckedUtcOffset = const Duration(hours: 9);

      final second = AppState();
      await second.initialized;
      expect(second.lastCheckedUtcOffset, const Duration(hours: 9));
    });

    test('lastReplanDate (FR-8/FR-17)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.lastReplanDate, isNull); // vor der allerersten Neuplanung

      final today = DateTime.utc(2026, 1, 15);
      first.lastReplanDate = today;

      final second = AppState();
      await second.initialized;
      expect(second.lastReplanDate, today);
    });

    test('pendingDayValues (FR-11) - über AppState und direkt über SharedPreferences lesbar', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      final values = <String, int?>{
        '2026-01-16': DateTime.utc(2026, 1, 16, 7, 0).millisecondsSinceEpoch,
        '2026-01-17': null, // kein Alarm geplant (z. B. Kaltstart, FR-10)
      };
      first.pendingDayValues = values;

      // Über eine neue AppState-Instanz (simuliert App-Neustart):
      final second = AppState();
      await second.initialized;
      expect(second.pendingDayValues, values);

      // Direkt über SharedPreferences, ohne AppState - genau der Zugriff, den
      // der Hintergrund-Isolate aus FR-16 Checkpoint 2 braucht:
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pendingDayValues');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded, values);
    });

    // Phase 4 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge"):
    // replan() needs wunschzeit/maxDailyDelta from AppState directly (FR-3) -
    // Phase 0 deliberately added only the 4 fields that don't need a settings
    // UI first (lastEffectiveWakeTime is derived from pendingDayValues
    // instead, see replan_test.dart); these two are added now, following the
    // exact same persistence pattern as the others.
    test('wunschzeit (FR-3/FR-4) - kein Standardwert, revisionierbar auf null', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.wunschzeit, isNull);

      first.wunschzeit = const TimeOfDay(hour: 7, minute: 30);
      final second = AppState();
      await second.initialized;
      expect(second.wunschzeit, const TimeOfDay(hour: 7, minute: 30));

      second.wunschzeit = null;
      final third = AppState();
      await third.initialized;
      expect(third.wunschzeit, isNull);
    });

    // FR-16/Phase 5 Schritt 22: Checkpoint 2 läuft im Hintergrund-Isolate ohne
    // AppState und muss unterscheiden können, welche Tageswerte instant- und
    // welche ziffern-verankert sind - daher persistiert, mit demselben
    // direkt-über-SharedPreferences-lesbaren Format wie pendingDayValues.
    test('pendingDayInstantAnchored (FR-16) - über AppState und direkt lesbar', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.pendingDayInstantAnchored, isEmpty);

      final anchored = <String, bool>{
        '2026-01-16': true, // Wert kam direkt aus einem echten hardFloor
        '2026-01-17': false, // wunschzeit/Kurve
      };
      first.pendingDayInstantAnchored = anchored;

      final second = AppState();
      await second.initialized;
      expect(second.pendingDayInstantAnchored, anchored);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pendingDayInstantAnchored');
      expect(raw, isNotNull);
      expect(jsonDecode(raw!), anchored);
    });

    // docs/TODO.md T-96: die Dauer der Gentle-Wake-Rampe war in
    // app_state.dart als `Duration(seconds: 60)` festverdrahtet.
    test('gentleWakeUpDuration - Rundreise und erzwungenes Minimum', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      // Standard = das bisher festverdrahtete Verhalten, damit bestehende
      // Installationen sich nicht plötzlich anders anhören.
      expect(first.gentleWakeUpDuration, const Duration(minutes: 1));

      first.gentleWakeUpDuration = const Duration(minutes: 10);
      final second = AppState();
      await second.initialized;
      expect(second.gentleWakeUpDuration, const Duration(minutes: 10));

      // Das Alarm-Plugin hat `assert(fadeDuration > Duration.zero)`. Der
      // hh:mm-Picker auf dem Sleep-Habits-Schirm lässt aber 00:00 zu, und im
      // Release-Build sind Assertions aus - eine Null käme also ungebremst im
      // Plugin an. Deshalb dieselbe Klammer wie bei maxDailyDelta.
      second.gentleWakeUpDuration = Duration.zero;
      expect(second.gentleWakeUpDuration, const Duration(minutes: 1));
    });

    test('maxDailyDelta (FR-3) - System-Minimum 15 Minuten wird erzwungen', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.maxDailyDelta, const Duration(minutes: 15)); // Standardwert = Minimum

      first.maxDailyDelta = const Duration(minutes: 45);
      final second = AppState();
      await second.initialized;
      expect(second.maxDailyDelta, const Duration(minutes: 45));

      // Ein Versuch, unter das Minimum zu gehen, wird auf 15min angehoben.
      second.maxDailyDelta = const Duration(minutes: 5);
      expect(second.maxDailyDelta, const Duration(minutes: 15));
    });
  });
}
