import 'package:flutter/foundation.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/utils.dart';

// FR-20 (docs/scheduling-v2-spec.md): Snooze verschiebt einen Weckruf, schaltet
// ihn aber nie ab.
//
// Bewusst eine eigene, plugin- und AppState-freie Datei mit reinen Funktionen:
// die Entscheidung "darf noch verschoben werden?" ist Rechnung, keine UI und
// kein Plattformzugriff, und sie wird an drei Stellen gebraucht (der
// Standard-Klingelschirm, der QR-Schirm und die Tests). Dieselbe Aufteilung wie
// bei `planAlarmSync`/`applyPlannedAlarms`.

/// Darf der Weckruf ein weiteres Mal verschoben werden?
///
/// Das Budget ist [wakeUpBudget] - `durationToWakeUp`, die Zeit zum Wachwerden
/// -, und das ist kein Zufall: FR-2 legt den Weckzeitpunkt auf
/// `frühester Termin − durationToWakeUp − durationToGetReady`. Snooze darf
/// ausschliesslich die erste Dauer aufbrauchen, nie die zum Fertigmachen.
/// Daraus folgt die tragende Zusicherung, ohne dass sie eigens geprueft werden
/// muss: **wer nur snoozet, kommt trotzdem rechtzeitig los.**
///
/// Gemessen wird ab [originalRing], dem *urspruenglichen* Weckzeitpunkt - nicht
/// ab dem letzten Druck. Wer den Wecker lange klingeln laesst, spart damit
/// nichts an; das Budget ist die Gesamtverschiebung, nicht die Anzahl der
/// Druecke.
///
/// Die Grenze ist einschliesslich: eine Verschiebung, die genau auf
/// `originalRing + wakeUpBudget` faellt, ist noch erlaubt.
bool canSnooze({
  required DateTime now,
  required DateTime originalRing,
  required Duration snoozeTime,
  required Duration wakeUpBudget,
  required bool snoozeEnabled,
}) {
  if (!snoozeEnabled) return false;
  final latestAllowed = originalRing.add(wakeUpBudget);
  return !snoozedRingTime(now: now, snoozeTime: snoozeTime)
      .isAfter(latestAllowed);
}

/// Wann der verschobene Weckruf klingelt.
///
/// Ab **jetzt**, nicht ab dem urspruenglichen Ruf: der Nutzer erwartet nach
/// einem Druck genau [snoozeTime] Ruhe, unabhaengig davon, wie lange er den
/// Wecker vorher hat laufen lassen.
DateTime snoozedRingTime({
  required DateTime now,
  required Duration snoozeTime,
}) =>
    now.add(snoozeTime);

/// Verschiebt den gerade klingelnden Weckruf um [AppState.snoozeTime].
///
/// Gibt `true` zurueck, wenn wirklich verschoben wurde. `false` heisst: es war
/// nicht erlaubt (Budget erschoepft oder Snooze aus) oder die Plattform hat den
/// neuen Ruf nicht angenommen - in beiden Faellen klingelt der Wecker weiter
/// bzw. bleibt unveraendert. **Nie** wird dabei ein Wecker abgeschaltet, ohne
/// dass ein neuer steht.
///
/// Zwei Dinge, die hier bewusst so sind (FR-20):
///
/// 1. Der verschobene Ruf ist ein **reiner Plattform-Alarm mit neuer ID**, den
///    `AppState` nicht als `ScheduledAlarm` fuehrt. Sonst wuerde FR-18 ihn beim
///    naechsten Abgleich entfernen: er liegt in der Zukunft und hat kein
///    geplantes Gegenstueck. Ein Plattform-Eintrag ohne Gegenstueck bleibt
///    dagegen unberuehrt (docs/TODO.md T-127).
/// 2. Der **Ursprungsruf wandert mit** auf die neue ID. Sonst begaenne das
///    Budget bei jedem Snooze von vorn, und "hoechstens `durationToWakeUp`"
///    waere wirkungslos.
Future<bool> snoozeRingingAlarm(
  AppState appState, {
  required int alarmId,
  required DateTime ringTime,
  DateTime Function()? now,
  required Future<void> Function(int id, DateTime at) setAlarm,
  required Future<void> Function(int id) stopAlarm,
  int Function()? newId,
}) async {
  final nowFn = now ?? DateTime.now;
  final origin = appState.snoozeOriginFor(alarmId) ?? ringTime;
  final at = nowFn();

  if (!canSnooze(
    now: at,
    originalRing: origin,
    snoozeTime: appState.snoozeTime,
    wakeUpBudget: durationFromTimeOfDay(appState.durationToWakeUp),
    snoozeEnabled: appState.snoozeEnabled,
  )) {
    return false;
  }

  final next = snoozedRingTime(now: at, snoozeTime: appState.snoozeTime);
  final id = (newId ?? getRandom)();

  // Erst den neuen Ruf stellen, dann den alten beenden: scheitert das Stellen,
  // klingelt der alte weiter - das ist der sichere Ausgang. Umgekehrt haette
  // ein Fehlschlag den Nutzer ohne jeden Wecker zurueckgelassen.
  try {
    await setAlarm(id, next);
  } catch (e) {
    debugPrint("=====snoozeRingingAlarm: setAlarm failed: ${e.runtimeType}");
    return false;
  }

  appState.rememberSnoozeOrigin(id, origin);
  appState.forgetSnoozeOrigin(alarmId);

  try {
    await stopAlarm(alarmId);
  } catch (e) {
    // Der neue Ruf steht bereits - das ist der Zustand, auf den es ankommt.
    debugPrint("=====snoozeRingingAlarm: stopAlarm failed: ${e.runtimeType}");
  }
  return true;
}
