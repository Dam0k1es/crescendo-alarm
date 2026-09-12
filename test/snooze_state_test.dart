import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/snooze.dart';

// FR-20 (docs/scheduling-v2-spec.md), docs/TODO.md T-138: Zustand und
// Vorgaben rund um Snooze.

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  group('FR-20: Vorgaben', () {
    test('Snooze ist aus, snoozeTime 5 Minuten, durationToWakeUp 00:00',
        () async {
      final appState = await _fresh();

      expect(appState.snoozeEnabled, isFalse);
      expect(appState.snoozeTime, const Duration(minutes: 5));
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 0),
          reason: 'FR-20 setzt die Vorgabe auf 00:00 - ohne Snooze gibt es '
              'keinen Grund, den Wecker vorzuziehen');
    });
  });

  group('FR-20: Einschalten macht das Budget brauchbar', () {
    test('bei 00:00 wird durationToWakeUp auf 00:10 gesetzt', () async {
      final appState = await _fresh();
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 0));

      appState.snoozeEnabled = true;

      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 10),
          reason: 'sonst waere das Budget null und die gerade eingeschaltete '
              'Funktion von Anfang an tot');
    });

    test('ein bereits gesetzter Wert bleibt unangetastet', () async {
      final appState = await _fresh();
      appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 45);

      appState.snoozeEnabled = true;

      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 45));
    });

    test('Ausschalten setzt das Budget nicht zurueck', () async {
      // Gegenprobe: der Nutzer soll seine Einstellung behalten, wenn er
      // Snooze nur kurz abschaltet.
      final appState = await _fresh();
      appState.snoozeEnabled = true;
      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 10));

      appState.snoozeEnabled = false;

      expect(appState.durationToWakeUp, const TimeOfDay(hour: 0, minute: 10));
    });
  });

  group('FR-20: Persistenz', () {
    test('snoozeEnabled und snoozeTime ueberstehen einen Neustart', () async {
      final first = await _fresh();
      first.snoozeEnabled = true;
      first.snoozeTime = const Duration(minutes: 12);

      final second = AppState();
      await second.initialized;
      expect(second.snoozeEnabled, isTrue);
      expect(second.snoozeTime, const Duration(minutes: 12));
    });

    test('der Ursprungsruf ueberlebt einen Prozesstod', () async {
      // Ohne ihn haette der Nutzer nach einem Neustart wieder das volle
      // Budget - Snooze waere dann unbegrenzt.
      final first = await _fresh();
      final ring = DateTime(2026, 9, 14, 6, 0);
      first.rememberSnoozeOrigin(4711, ring);

      final second = AppState();
      await second.initialized;
      expect(second.snoozeOriginFor(4711), ring);
    });

    test('ein abgeschlossener Weckruf wird vergessen', () async {
      final appState = await _fresh();
      appState.rememberSnoozeOrigin(4711, DateTime(2026, 9, 14, 6, 0));

      appState.forgetSnoozeOrigin(4711);

      expect(appState.snoozeOriginFor(4711), isNull);
    });
  });

  group('FR-20: der Vorgang selbst', () {
    late List<({int id, DateTime at})> gesetzt;
    late List<int> gestoppt;

    Future<bool> snooze(AppState appState,
        {required int alarmId,
        required DateTime ringTime,
        required DateTime now,
        bool setzenSchlaegtFehl = false}) {
      gesetzt = [];
      gestoppt = [];
      return snoozeRingingAlarm(
        appState,
        alarmId: alarmId,
        ringTime: ringTime,
        now: () => now,
        newId: () => 999,
        setAlarm: (id, at) async {
          if (setzenSchlaegtFehl) throw StateError('Plattform weg');
          gesetzt.add((id: id, at: at));
        },
        stopAlarm: (id) async => gestoppt.add(id),
      );
    }

    test('verschiebt um snoozeTime und beendet den alten Ruf', () async {
      final appState = await _fresh();
      appState.snoozeEnabled = true; // setzt das Budget auf 00:10
      final ring = DateTime(2026, 9, 14, 6, 0);

      final ok = await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 0));

      expect(ok, isTrue);
      expect(gesetzt.single.at, DateTime(2026, 9, 14, 6, 5));
      expect(gestoppt, [1]);
    });

    test('der Ursprungsruf wandert auf die neue ID mit', () async {
      // Ohne das begaenne das Budget bei jedem Snooze von vorn.
      final appState = await _fresh();
      appState.snoozeEnabled = true;
      final ring = DateTime(2026, 9, 14, 6, 0);

      await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 0));

      expect(appState.snoozeOriginFor(999), ring);
      expect(appState.snoozeOriginFor(1), isNull);
    });

    test('am Budgetende wird nicht mehr verschoben - und nichts gestoppt',
        () async {
      final appState = await _fresh();
      appState.snoozeEnabled = true; // Budget 10min
      final ring = DateTime(2026, 9, 14, 6, 0);

      final ok = await snooze(appState,
          alarmId: 1, ringTime: ring, now: DateTime(2026, 9, 14, 6, 6));

      expect(ok, isFalse, reason: '06:06 + 5min = 06:11 > 06:10');
      expect(gesetzt, isEmpty);
      expect(gestoppt, isEmpty,
          reason: 'FR-20: Snooze schaltet nie ab - scheitert es, klingelt der '
              'Wecker weiter');
    });

    test('scheitert das Stellen, bleibt der alte Wecker scharf', () async {
      final appState = await _fresh();
      appState.snoozeEnabled = true;

      final ok = await snooze(appState,
          alarmId: 1,
          ringTime: DateTime(2026, 9, 14, 6, 0),
          now: DateTime(2026, 9, 14, 6, 0),
          setzenSchlaegtFehl: true);

      expect(ok, isFalse);
      expect(gestoppt, isEmpty,
          reason: 'sonst stuende der Nutzer ohne jeden Wecker da');
    });

    test('abgeschaltet passiert nichts', () async {
      final appState = await _fresh(); // snoozeEnabled ist aus

      final ok = await snooze(appState,
          alarmId: 1,
          ringTime: DateTime(2026, 9, 14, 6, 0),
          now: DateTime(2026, 9, 14, 6, 0));

      expect(ok, isFalse);
      expect(gesetzt, isEmpty);
      expect(gestoppt, isEmpty);
    });
  });
}
