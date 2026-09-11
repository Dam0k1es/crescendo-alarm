import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/apply_alarms.dart';
import 'package:flutter/material.dart' show TimeOfDay;

// docs/TODO.md T-63: replan() berechnete die Woche korrekt in
// pendingDayValues, aber NICHTS machte daraus je einen echten Alarm - das
// Weckverhalten kam weiterhin ausschließlich vom alten Scheduler. Diese Datei
// spezifiziert die fehlende Brücke: pendingDayValues -> ScheduledAlarms.
//
// Wichtig für die Testbarkeit: appState.addAlarm() lehnt Zeiten in der
// Vergangenheit ab (echtes DateTime.now(), nicht injizierbar) - die
// Applier-Tests nutzen deshalb echte Zukunftszeiten, die reinen
// planAlarmSync-Tests dagegen feste, injizierte "now"-Werte.

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

ScheduledAlarm _alarmAt(DateTime time, {int id = 1, double volume = 0.8}) =>
    ScheduledAlarm(
      time: time,
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      volume: volume,
      id: id,
    );

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  group('planAlarmSync (T-63, rein)', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('nichts geplant, nichts vorhanden -> keine Änderung', () {
      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });

    test('zukünftiger geplanter Wert ohne bestehenden Alarm -> wird angelegt', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, [planned]);
      expect(plan.toRemove, isEmpty);
    });

    test('passender Alarm existiert bereits -> kein Duplikat, keine Entfernung', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned)],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });

    test('bestehender Alarm, der nicht mehr geplant ist -> wird entfernt', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final stale = _alarmAt(DateTime(2026, 3, 11, 9, 0), id: 2);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [stale],
        now: now,
      );

      expect(plan.toAdd, [planned]);
      expect(plan.toRemove, [stale]);
    });

    test('FR-11: ein bereits vergangener (geklingelter) geplanter Wert wird nicht neu gesetzt', () {
      final past = DateTime(2026, 3, 9, 7, 0);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(past): past.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });

    test('null-Wert (Lückentag/Sicherheitsventil) erzeugt keinen Alarm und entfernt einen bestehenden',
        () {
      final day = DateTime(2026, 3, 11);
      final existing = _alarmAt(DateTime(2026, 3, 11, 7, 30), id: 3);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(day): null},
        existingScheduledAlarms: [existing],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, [existing]);
    });

    // Sicherheitskritisch: der Ring-Checkpoint (FR-8) läuft, WÄHREND ein Alarm
    // klingelt - dessen eigene Zeit liegt dann gerade in der Vergangenheit.
    // Würde der Sync ihn als "nicht mehr geplant" entfernen, würde
    // AppState.removeAlarm() ihn per Alarm.stop() mitten im Klingeln
    // verstummen lassen und damit das "garantierte Aufwachen" aushebeln.
    test('ein bestehender Alarm in der Vergangenheit wird NIE entfernt (könnte gerade klingeln)',
        () {
      final ringing = _alarmAt(DateTime(2026, 3, 10, 5, 55), id: 4);

      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: [ringing],
        now: now, // 06:00 - der Alarm hat also gerade geklingelt
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    // Lasttragende Invariante: replan()s Fenster beginnt immer MORGEN (der
// geklingelte Tag ist fix, FR-11), heutiger Tageswert steht also nur noch
    // deshalb in pendingDayValues, weil replan() alte Einträge NICHT prunt.
    // Szenario: gestern wurde heute 07:00 geplant, heute 03:00 läuft ein
    // Checkpoint (z. B. FR-17 nach Reboot). Der heute-Alarm liegt noch in der
    // Zukunft und muss erhalten bleiben - würde man pendingDayValues
    // "aufräumen", würde dieser Sync ihn löschen und der Nutzer verschlafen.
    test('heutiger, noch nicht geklingelter Alarm bleibt erhalten, obwohl das Fenster erst morgen beginnt',
        () {
      final todayValue = DateTime(2026, 3, 10, 7, 0); // gestern für heute geplant
      final tomorrowValue = DateTime(2026, 3, 11, 7, 30); // aus dem neuen Fenster
      final existingToday = _alarmAt(todayValue, id: 7);

      final plan = planAlarmSync(
        pendingDayValues: {
          _iso(todayValue): todayValue.millisecondsSinceEpoch,
          _iso(tomorrowValue): tomorrowValue.millisecondsSinceEpoch,
        },
        existingScheduledAlarms: [existingToday],
        now: DateTime(2026, 3, 10, 3, 0), // 03:00 heute, vor dem Alarm
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, [tomorrowValue]);
    });

    // docs/TODO.md T-74e: AppState und Plattform können auseinanderlaufen (der
    // QR-Dismiss stoppte früher ALLE gespeicherten Alarme, ohne die
    // AppState-Listen anzupassen). Dann war dieser Sync ein No-op und der
    // Nutzer stand ohne Alarm da.
    test('geplanter Tag, dessen Alarm auf der Plattform fehlt -> wird neu gesetzt',
        () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final stale = _alarmAt(planned, id: 9);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [stale],
        now: now,
        platformAlarmIds: const {}, // Plattform hat gar nichts mehr
      );

      expect(plan.toRemove, [stale]); // veralteter AppState-Eintrag raus
      expect(plan.toAdd, [planned]); // und frisch setzen
    });

    test('ist die Plattform deckungsgleich, bleibt der Sync ein No-op', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 9)],
        now: now,
        platformAlarmIds: {9},
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    // docs/TODO.md T-84: der Abgleich verglich ausschließlich die Minute, also
    // wirkte eine geänderte Ton-/Lautstärke-/Gentle-Wake-Einstellung erst,
    // wenn ein Tag ohnehin neu geplant wurde - für bereits gesetzte Alarme
    // also unter Umständen nie.
    group('T-84: Eigenschaften gehören zum Abgleich', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      test('abweichender Ton -> Alarm wird ersetzt', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: false,
              tone: 'assets/sounds/alt.mp3',
              id: 11,
            )
          ],
          now: now,
          tone: 'assets/sounds/lollipop.mp3',
        );

        expect(plan.toRemove.single.id, 11);
        expect(plan.toAdd, [planned]);
      });

      test('abweichende Lautstärke -> Alarm wird ersetzt', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [_alarmAt(planned, id: 12, volume: 0.2)],
          now: now,
          volume: 0.9,
        );

        expect(plan.toRemove.single.id, 12);
        expect(plan.toAdd, [planned]);
      });

      test('abweichendes Gentle-Wake -> Alarm wird ersetzt', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: false,
              tone: 'assets/sounds/lollipop.mp3',
              id: 13,
            )
          ],
          now: now,
          gentleWake: true,
        );

        expect(plan.toRemove.single.id, 13);
        expect(plan.toAdd, [planned]);
      });

      // docs/TODO.md T-96: dieselbe Lehre wie bei Ton und Lautstärke - eine
      // Einstellung, die `planAlarmSync` nicht vergleicht, wirkt auf bereits
      // gesetzte Alarme nie.
      test('abweichende Gentle-Wake-Dauer -> Alarm wird ersetzt', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: true,
              tone: 'assets/sounds/lollipop.mp3',
              volume: 0.8,
              gentleWakeDuration: const Duration(minutes: 1),
              id: 21,
            )
          ],
          now: now,
          gentleWake: true,
          gentleWakeDuration: const Duration(minutes: 10),
        );

        expect(plan.toRemove.single.id, 21);
        expect(plan.toAdd, [planned]);
      });

      test('identische Eigenschaften -> weiterhin ein No-op', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [_alarmAt(planned, id: 14, volume: 0.8)],
          now: now,
          tone: 'assets/sounds/lollipop.mp3',
          volume: 0.8,
          gentleWake: false,
        );

        expect(plan.toRemove, isEmpty);
        expect(plan.toAdd, isEmpty);
      });

      // Ohne Angabe (der bisherige Aufrufweg) bleibt der Vergleich rein
      // zeitbasiert - so kann kein Aufrufer versehentlich alle Alarme
      // neu setzen, nur weil er die Eigenschaften nicht kennt.
      test('ohne angegebene Eigenschaften wird nur die Zeit verglichen', () {
        final plan = planAlarmSync(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          existingScheduledAlarms: [
            ScheduledAlarm(
              time: planned,
              enabled: true,
              gentlewake: true,
              tone: 'assets/sounds/irgendwas.mp3',
              id: 15,
            )
          ],
          now: now,
        );

        expect(plan.toRemove, isEmpty);
        expect(plan.toAdd, isEmpty);
      });
    });

    // docs/TODO.md T-88: platformAlarmTimes kam aus Alarm.getAlarms() und
    // enthielt damit auch ManualAlarm-Zeiten. Ein ScheduledAlarm auf derselben
    // Minute galt dadurch fälschlich als "auf der Plattform vorhanden".
    test('T-88: ein fremder Plattform-Alarm auf derselben Minute deckt nichts ab',
        () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 16)],
        // Die Plattform kennt die Minute - aber nicht unter der id dieses
        // ScheduledAlarms (z. B. weil dort ein ManualAlarm liegt).
        platformAlarmIds: const {999},
        now: now,
      );

      expect(plan.toRemove.single.id, 16);
      expect(plan.toAdd, [planned]);
    });

    test('T-88: der eigene Plattform-Eintrag deckt ihn ab', () {
      final planned = DateTime(2026, 3, 11, 7, 30);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 17)],
        platformAlarmIds: const {17},
        now: now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    test('Vergleich ist minutengenau (Sekunden/Millisekunden erzeugen kein Duplikat)', () {
      final planned = DateTime(2026, 3, 11, 7, 30, 45, 123);
      final existing = _alarmAt(DateTime(2026, 3, 11, 7, 30), id: 5);

      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [existing],
        now: now,
      );

      expect(plan.toAdd, isEmpty);
      expect(plan.toRemove, isEmpty);
    });
  });

  group('applyPlannedAlarms (T-63, gegen echten AppState)', () {
    test('legt für einen geplanten Zukunftswert einen ScheduledAlarm an', () async {
      final appState = await _freshAppState();
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.length, 1);
      expect(appState.scheduledAlarms.single.time.hour, planned.hour);
      expect(appState.scheduledAlarms.single.time.minute, planned.minute);
    });

    test('entfernt einen ScheduledAlarm, der nicht mehr geplant ist', () async {
      final appState = await _freshAppState();
      final obsolete = DateTime.now().add(const Duration(days: 2));
      appState.scheduledAlarms = [_alarmAt(obsolete, id: 42)];
      appState.pendingDayValues = const {};

      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms, isEmpty);
    });

    test('FR-15: ManualAlarms bleiben vollkommen unberührt', () async {
      final appState = await _freshAppState();
      final manualAlarm = ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0));
      appState.manualAlarms.add(manualAlarm);
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      expect(appState.manualAlarms, [manualAlarm]);
      expect(appState.manualAlarms.single.time,
          const TimeOfDay(hour: 3, minute: 0));
    });

    // docs/TODO.md T-84: ScheduledAlarm hatte kein volume-Feld, also klangen
    // alle von FR-18 gesetzten Alarme mit MyAlarms Default 0.6 und ignorierten
    // appState.selectedVolume - obwohl es dafür eine UI gibt.
    test('T-84: übernimmt Ton, Lautstärke und Gentle-Wake aus den Einstellungen',
        () async {
      final appState = await _freshAppState();
      appState.selectedTone = 'assets/sounds/alt.mp3';
      appState.selectedVolume = 0.35;
      appState.gentleWakeUpEnabled = true;
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      final alarm = appState.scheduledAlarms.single;
      expect(alarm.tone, 'assets/sounds/alt.mp3');
      expect(alarm.volume, 0.35);
      expect(alarm.gentlewake, isTrue);
    });

    test('T-84: eine geänderte Lautstärke wirkt auf bereits geplante Alarme',
        () async {
      final appState = await _freshAppState();
      appState.selectedVolume = 0.35;
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };
      await applyPlannedAlarms(appState);
      expect(appState.scheduledAlarms.single.volume, 0.35);

      appState.selectedVolume = 0.9;
      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.single.volume, 0.9);
      expect(appState.scheduledAlarms.length, 1);
    });

    test('T-96: übernimmt die Gentle-Wake-Dauer aus den Einstellungen', () async {
      final appState = await _freshAppState();
      appState.gentleWakeUpEnabled = true;
      appState.gentleWakeUpDuration = const Duration(minutes: 7);
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.single.gentleWakeDuration,
          const Duration(minutes: 7));
    });

    test('T-96: eine geänderte Dauer wirkt auf bereits geplante Alarme', () async {
      final appState = await _freshAppState();
      appState.gentleWakeUpEnabled = true;
      appState.gentleWakeUpDuration = const Duration(minutes: 2);
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };
      await applyPlannedAlarms(appState);
      expect(appState.scheduledAlarms.single.gentleWakeDuration,
          const Duration(minutes: 2));

      appState.gentleWakeUpDuration = const Duration(minutes: 12);
      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.single.gentleWakeDuration,
          const Duration(minutes: 12));
      expect(appState.scheduledAlarms.length, 1);
    });

    test('ist idempotent: ein zweiter Aufruf ändert nichts', () async {
      final appState = await _freshAppState();
      final planned = DateTime.now().add(const Duration(days: 1));
      appState.pendingDayValues = {
        _iso(planned): planned.millisecondsSinceEpoch,
      };

      await applyPlannedAlarms(appState);
      final afterFirst = List<ScheduledAlarm>.from(appState.scheduledAlarms);
      await applyPlannedAlarms(appState);

      expect(appState.scheduledAlarms.length, afterFirst.length);
      expect(appState.scheduledAlarms.single.id, afterFirst.single.id);
    });
  });

  group('FR-18: zwei Alarme auf derselben Minute (T-116)', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    // FR-18s Kopfsatz ist eine Nachbedingung ueber die MENGE:
    //
    //   "Nach jeder Neuplanung wird die Menge der `ScheduledAlarm`s so
    //    angeglichen, dass sie **genau den geplanten Werten entspricht**"
    //
    // und FR-18s eigener Testfall formuliert dasselbe Ziel:
    // "passender Alarm existiert bereits -> kein Duplikat, keine Entfernung
    // (idempotent)".
    //
    // Die zweite Spiegelstrich-Regel ("ein Alarm, der KEINEM geplanten Wert
    // entspricht, wird entfernt") ist dagegen eine Bedingung pro Alarm, und
    // auf ein Duplikat trifft sie bei keinem der beiden zu. Massgeblich ist
    // der Kopfsatz: er nennt das Ziel, die Spiegelstriche die Mittel.
    //
    // Unabhaengig von jeder Spec-Auslegung verfehlt die Funktion hier ihren
    // EIGENEN dokumentierten Vertrag: "computes what has to change so the set
    // of ScheduledAlarms matches pendingDayValues **exactly**".

    test('ein geplanter Wert, zwei passende Alarme -> genau einer bleibt', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [
          _alarmAt(planned, id: 1),
          _alarmAt(planned, id: 2),
        ],
        platformAlarmIds: const {1, 2},
        now: now,
      );

      expect(plan.toRemove.length, 1, reason: 'genau das Duplikat faellt weg');
      expect(plan.toAdd, isEmpty, reason: 'der ueberlebende deckt den Wert ab');
      // Der Ueberlebende muss eine ANDERE id tragen als der Entfernte:
      // `applyPlannedAlarms` entfernt ueber die id, ein Entfernen derselben id
      // wuerde den Ueberlebenden auf der Plattform mitstoppen.
      expect(plan.toRemove.single.id, isNot(1));
    });

    test('nach dem Aufraeumen ist der naechste Lauf ein Fixpunkt', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 1)],
        platformAlarmIds: const {1},
        now: now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    test('drei auf derselben Minute -> zwei fallen weg', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [
          _alarmAt(planned, id: 1),
          _alarmAt(planned, id: 2),
          _alarmAt(planned, id: 3),
        ],
        platformAlarmIds: const {1, 2, 3},
        now: now,
      );

      expect(plan.toRemove.length, 2);
      expect(plan.toAdd, isEmpty);
    });

    test('ein Duplikat in der VERGANGENHEIT wird nie entfernt', () {
      // FR-18s sicherheitskritische Regel bleibt unberuehrt: "Ein
      // ScheduledAlarm in der Vergangenheit wird NIE entfernt (er koennte
      // gerade klingeln; Alarm.stop() wuerde das garantierte Aufwachen
      // aushebeln)."
      final past = DateTime(2026, 3, 10, 5, 55);
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [
          _alarmAt(past, id: 1),
          _alarmAt(past, id: 2),
          _alarmAt(planned, id: 3),
        ],
        platformAlarmIds: const {1, 2, 3},
        now: now,
      );

      expect(plan.toRemove, isEmpty,
          reason: 'beide Vergangenheits-Alarme bleiben unangetastet');
      expect(plan.toAdd, isEmpty);
    });

    test('zwei Alarme auf VERSCHIEDENEN Minuten bleiben beide', () {
      // Gegenprobe gegen eine Ueberkorrektur.
      final a = DateTime(2026, 3, 11, 7, 30);
      final b = DateTime(2026, 3, 12, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {
          _iso(a): a.millisecondsSinceEpoch,
          _iso(b): b.millisecondsSinceEpoch,
        },
        existingScheduledAlarms: [_alarmAt(a, id: 1), _alarmAt(b, id: 2)],
        platformAlarmIds: const {1, 2},
        now: now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
    });
  });
}
