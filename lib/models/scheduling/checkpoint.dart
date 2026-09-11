// Der eine Einstiegspunkt für scheduling-v2 (docs/TODO.md T-87, behebt T-77
// und T-80).
//
// Vorher gab es fünf: replan(), runAlarmRingCheckpoint(),
// onAppForegroundCheckpoint(), runForegroundCheckpointSafely() und
// onSchedulingSettingsChanged(). Sie unterschieden sich in vier orthogonalen
// Dimensionen - schreibt der Aufrufer den Zeitzonen-Versatz fort? gilt heute
// als abgeschlossen? werden FR-6/9/12 gemeldet? wird die Bettzeit-Notification
// neu geplant? werden Fehler geschluckt? - und jede Kombination war irgendwo
// von Hand zusammengesetzt. Genau diese Matrix hat T-67 (Melden fehlte auf dem
// Erholungspfad), T-71 (heute fälschlich als abgeschlossen behandelt) und T-80
// (Reminder fehlte in beiden Checkpoints) produziert: dreimal derselbe Fehler
// in derselben Struktur.
//
// Hier steht die Sequenz genau einmal, vollständig und serialisiert. Was sich
// je Auslöser unterscheidet, ist ausschließlich [CheckpointTrigger] - und das
// steht als Tabelle in [runSchedulingCheckpoint]s Doc-Kommentar, nicht implizit
// in fünf Aufrufstellen.
//
// Liegt bewusst in einer eigenen Datei, nicht in replan.dart: die Sequenz
// braucht sleep_reminder.dart, und das zieht über notifications.dart einen
// Import-Zyklus zurück auf replan.dart (FR-16 Checkpoint 2).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/models/scheduling/replan_notifications.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/sleep_reminder.dart';

/// Was den Checkpoint ausgelöst hat. Der einzige Unterschied zwischen den
/// Abläufen - siehe die Tabelle in [runSchedulingCheckpoint].
enum CheckpointTrigger {
  /// FR-8/FR-16 Checkpoint 1: ein Alarm hat gerade geklingelt. Der einzige
  /// Auslöser, für den der heutige Tag abgeschlossen ist (FR-11).
  alarmRing,

  /// FR-17: die App kam in den Vordergrund (Kaltstart nach Reboot/Force-Quit
  /// oder ein normales Resume). Unterliegt FR-17s Tagessperre.
  appForeground,

  /// docs/TODO.md T-65: eine Einstellung, die in die Rechnung eingeht, hat
  /// sich geändert. Unterliegt der Tagessperre bewusst **nicht** - eine
  /// Änderung muss sofort wirken.
  settingsChanged,

  /// Der Nutzer hat den Sync-Knopf in der Alarmliste gedrückt (Phase 6,
  /// docs/TODO.md T-64 - dort lief vorher der alte Scheduler). Verhält sich
  /// wie [settingsChanged]; eigener Wert, damit die Tabelle unten und die
  /// Debug-Ausgabe ehrlich bleiben.
  manualSync,
}

/// Serialisiert alle Checkpoints gegeneinander (docs/TODO.md T-77).
///
/// Nötig, weil drei der vier Auslöser fire-and-forget sind (`unawaited`) und
/// FR-17s Tagessperre sie nicht schützen kann: die liest `lastReplanDate`,
/// das erst am **Ende** von `replan()` geschrieben wird. Klingelt ein Alarm,
/// holt Android die App per Full-Screen-Intent nach vorn, also feuert
/// unmittelbar auch der Resume-Auslöser - der zweite Checkpoint startete
/// mitten im Kalender-I/O des ersten. Folge: `gapDayCounter` doppelt
/// inkrementiert (FR-9s Ventil verrechnet sich) und beide berechneten `toAdd`
/// gegen dieselbe alte Alarmliste, also Doppelalarme auf derselben Minute.
Future<void> _tail = Future<void>.value();

/// Wie viele Checkpoints gerade anstehen. Nur fuer die Diagnose: ein Wert > 0
/// beim Start belegt genau die Verschraenkung, die T-77 war (Ring holt die App
/// per Full-Screen-Intent nach vorn, also feuert unmittelbar auch Resume).
int _pending = 0;

Future<T> _serialized<T>(Future<T> Function() body) {
  final completer = Completer<T>();
  _pending++;
  _tail = _tail.then((_) async {
    try {
      completer.complete(await body());
    } catch (error, stack) {
      // Der Fehler geht an den eigenen Aufrufer; die Kette selbst bleibt
      // heil, damit ein kaputter Checkpoint nicht alle folgenden blockiert.
      completer.completeError(error, stack);
    } finally {
      _pending--;
    }
  });
  return completer.future;
}

/// Die vollständige Reaktion auf einen Auslöser, in fester Reihenfolge:
///
/// 1. serialisieren (T-77),
/// 2. FR-17s Tagessperre prüfen (nur [CheckpointTrigger.appForeground]),
/// 3. den aktuellen Zeitzonen-Versatz festhalten (FR-16),
/// 4. [replan] - inklusive FR-18s Alarmabgleich, den `replan()` selbst anstößt,
/// 5. FR-6/FR-9/FR-12 melden ([reportReplanNotifications]),
/// 6. die Bettzeit-Notification neu planen ([scheduleSleepReminder], T-80).
///
/// | Auslöser | heute abgeschlossen (FR-11) | Tagessperre (FR-17) |
/// |---|---|---|
/// | `alarmRing` | ja | nein |
/// | `appForeground` | nein | ja |
/// | `settingsChanged` | nein | nein |
/// | `manualSync` | nein | nein |
///
/// Gibt `null` zurück, wenn FR-17s Tagessperre gegriffen hat (kein I/O,
/// nichts geändert), sonst das Ergebnis der Neuplanung.
///
/// Wirft weiter, wenn die Neuplanung scheitert - wer das nicht verkraftet
/// (UI-Pfade), nimmt [runCheckpointSafely].
Future<ReplanResult?> runSchedulingCheckpoint(
  AppState appState, {
  required CheckpointTrigger trigger,
  FetchEvents? fetchEvents,
  DateTime Function()? now,
  Duration? deviceUtcOffset,
  Notifications? notifications,
}) {
  // Vor der Serialisierung gemessen, damit die Wartezeit auf einen laufenden
  // Checkpoint ueberhaupt sichtbar wird.
  final queuedBehind = _pending;
  final clock = Stopwatch()..start();

  return _serialized(() async {
    final nowFn = now ?? DateTime.now;
    final currentTime = nowFn();
    final offset = deviceUtcOffset ?? currentTime.timeZoneOffset;

    Diag.checkpointStarted(
      trigger: diagTriggerOf(trigger),
      queueDepth: queuedBehind,
      waited: bucketMillis(clock.elapsedMilliseconds),
    );

    if (trigger == CheckpointTrigger.appForeground) {
      // FR-17: ein zweites App-Öffnen am selben Tag ist ein No-op. Innerhalb
      // der Serialisierung gelesen, damit der Wert nicht von einem parallel
      // laufenden Checkpoint stammt, der ihn gleich noch schreiben wird.
      //
      // Die Bedingung ist **Gleichheit**, nicht "nicht vor heute"
      // (docs/TODO.md T-109). FR-17 sagt wörtlich "Ist `lastReplanDate` ≠
      // heutiges Kalenderdatum: sofort […] Sonst: kein zusätzlicher
      // Checkpoint" - und ein `>=` verschluckt zusätzlich den Fall, in dem der
      // Marker in der ZUKUNFT liegt.
      //
      // Dorthin gerät er ohne jedes Zutun der App: er ist ein gerätelokales
      // Ziffern-Datum ohne Klammerung, und ein Zonenwechsel über die
      // Datumsgrenze (Apia +13 → Pago Pago −11) oder eine Rückwärtskorrektur
      // der Systemuhr lässt das lokale Datum zurückspringen. Gemessen wurden
      // dabei bis zu ~48 lokale Stunden ohne einen einzigen
      // Vordergrund-Checkpoint - also ohne den ungecachten Kalender-Neuread,
      // der einen veralteten Plan reparieren würde. Ein Ring repariert den
      // Marker nebenbei, aber genau in FR-17s drei Lücken (Reboot,
      // Force-Quit, ausgefallenes Klingeln) gibt es keinen.
      //
      // Verglichen wird über `dayDistance`, nicht über `==` auf zwei
      // `DateTime`: der Marker kommt lokal getaggt aus den Preferences,
      // `currentTime` kann ein `tz.TZDateTime` sein, und Darts `==` verlangt
      // denselben `isUtc`-Frame. Das ist die Fehlerklasse dieses Moduls
      // (T-61/T-76/T-83) - `dayDistance` vergleicht bewusst die Datumsziffern.
      final lastReplanDate = appState.lastReplanDate;
      if (lastReplanDate != null &&
          dayDistance(currentTime, midnight(lastReplanDate)) == 0) {
        Diag.checkpointSkipped(
          trigger: diagTriggerOf(trigger),
          daysSinceLastReplan: 0,
        );
        return null;
      }
    }

    var outcome = CheckpointOutcome.replanThrew;

    // FR-16: den geprüften Versatz unabhängig davon festhalten, ob sich
    // etwas geändert hat - sonst würde Checkpoint 2 dieselbe Änderung
    // dauerhaft neu entdecken. Bewusst vor der Neuplanung, damit ein
    // Kalenderfehler den Versatz nicht veralten lässt.
    appState.lastCheckedUtcOffset = offset;

    try {
      final result = await replan(
        appState,
        fetchEvents: fetchEvents,
        now: now,
        deviceUtcOffset: deviceUtcOffset,
        // FR-11: nur der tatsächlich ausgelöste Wert ist fix (docs/TODO.md
        // T-71). Für Erholung und Einstellungsänderung hat heute noch nicht
        // geklingelt, bleibt also revidierbar und ungezählt.
        todayAlreadyRang: trigger == CheckpointTrigger.alarmRing,
      );

      await reportReplanNotifications(appState, result,
          notifications: notifications);

      outcome = CheckpointOutcome.ok;
      return result;
    } catch (e) {
      Diag.failure(
        at: DiagEvent.checkpointFinished,
        exceptionType: e.runtimeType,
        kind: ErrorKind.plugin,
      );
      rethrow;
    } finally {
      // docs/TODO.md T-80: die Bettzeit leitet sich aus dem frisch geplanten
      // Weckzeitpunkt ab, muss also nach der Neuplanung laufen - und in JEDEM
      // Auslöser, nicht nur beim Dismiss und beim Reminder-Schalter. Sonst
      // feuert FR-16s Checkpoint 2 zu einem Zeitpunkt ohne Bezug zum Plan.
      //
      // Im `finally`, damit ein gescheiterter Kalenderzugriff FR-16s Aufhänger
      // nicht mitreißt: auf einem frischen Install gibt es noch überhaupt
      // keine Bettzeit-Notification, und ohne sie fehlt Checkpoint 2 dauerhaft
      // der Einsprungpunkt. `scheduleSleepReminder` schluckt eigene Fehler
      // selbst, kann diesen Pfad also nicht zusätzlich zum Scheitern bringen.
      await scheduleSleepReminder(appState, notifications: notifications);

      Diag.checkpointFinished(
        trigger: diagTriggerOf(trigger),
        outcome: outcome,
        took: bucketMillis(clock.elapsedMilliseconds),
      );
      // Gebuendelt am Ende der Sequenz persistieren - der Klingelpfad selbst
      // bekommt so keine I/O-Latenz.
      await Diag.flush();
    }
  });
}

/// [runSchedulingCheckpoint] für Aufrufer, die nicht scheitern dürfen: jeder
/// UI- und Lifecycle-Pfad (App-Start, Resume, Einstellungsänderung). Ein
/// echter Kalender-Plugin-Aussetzer darf weder den App-Start abbrechen noch
/// die UI abstürzen lassen, die die Änderung ausgelöst hat.
Future<ReplanResult?> runCheckpointSafely(
  AppState appState, {
  required CheckpointTrigger trigger,
  FetchEvents? fetchEvents,
  DateTime Function()? now,
  Duration? deviceUtcOffset,
  Notifications? notifications,
}) async {
  try {
    return await runSchedulingCheckpoint(
      appState,
      trigger: trigger,
      fetchEvents: fetchEvents,
      now: now,
      deviceUtcOffset: deviceUtcOffset,
      notifications: notifications,
    );
  } catch (e) {
    debugPrint("=====runCheckpointSafely: $trigger failed: ${e.runtimeType}");
    return null;
  }
}

/// Uebersetzt den Auslöser in den stabilen Diagnose-Code.
///
/// Der Logger fuehrt absichtlich eine eigene Enum: er soll nicht in die
/// Scheduling-Schicht importieren, und die exportierten Codes muessen stabil
/// bleiben, auch wenn hier ein Auslöser dazukommt.
DiagTrigger diagTriggerOf(CheckpointTrigger trigger) => switch (trigger) {
      CheckpointTrigger.alarmRing => DiagTrigger.alarmRing,
      CheckpointTrigger.appForeground => DiagTrigger.appForeground,
      CheckpointTrigger.settingsChanged => DiagTrigger.settingsChanged,
      CheckpointTrigger.manualSync => DiagTrigger.manualSync,
    };
