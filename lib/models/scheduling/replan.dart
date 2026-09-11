// AppState-aware scheduling-v2 orchestration (docs/scheduling-v2-spec.md,
// "Architektur", "AppState-bewusste Orchestrierung"). Unlike scheduling_v2.dart,
// these functions DO take AppState directly and perform I/O (calendar reads) -
// but every external dependency (calendar fetch, current time, device offset)
// is injectable, so they stay unit-testable without a device/emulator or a
// mocked plugin channel (see test/replan_test.dart).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/apply_alarms.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/models/scheduling/stored_values.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/utils.dart';

typedef FetchEvents = Future<List<Meeting>> Function(DateTime start, DateTime end);

/// FR-6/FR-9/FR-12's respective notification flags, bubbled up from a single
/// `replan()` call - plain data, no side effect: actually showing a
/// notification for any of these is Phase 5's job (platform wiring).
class ReplanResult {
  const ReplanResult({
    required this.overrunNotificationNeeded,
    required this.safetyValveTriggered,
    required this.possiblyMissedAppointment,
  });

  final bool overrunNotificationNeeded;
  final bool safetyValveTriggered;
  final bool possiblyMissedAppointment;
}

/// FR-8: the full daily replanning checkpoint. Never touches `ManualAlarm`s
/// (FR-15) - it only ever reads/writes the `ScheduledAlarm`-related
/// scheduling-v2 fields on [appState].
///
/// Not called directly by app code - `runSchedulingCheckpoint`
/// (`checkpoint.dart`) is the one entry point, and it decides
/// [todayAlreadyRang] from its trigger.
///
/// The day that "just rang" (or, on FR-17's recovery path, today's real
/// calendar date) is [now]'s date - it becomes the new fixed anchor (FR-11:
/// "Erst der tatsächlich ausgelöste Wert ist für immer fix"), and the fresh
/// 7-day window (FR-8: "kein erweiterter Berechnungshorizont") starts the day
/// after it. If more than one calendar day has elapsed since
/// [AppState.lastProcessedConcludedDay] (e.g. a reboot gap, FR-17), every
/// skipped day in between is walked individually so FR-9's `gapDayCounter` and
/// FR-12's missed-appointment check both reflect each of them, not just the
/// most recent one.
Future<ReplanResult> replan(
  AppState appState, {
  FetchEvents? fetchEvents,
  DateTime Function()? now,
  Duration? deviceUtcOffset,
  bool todayAlreadyRang = false,
}) async {
  // docs/TODO.md T-69: FR-16's Checkpoint 2 writes these fields straight to
  // SharedPreferences from a background isolate, so a live AppState's
  // in-memory copy can be stale. Merging on top of a stale copy silently
  // reverted the checkpoint's reinterpretation, so re-read first.
  await appState.reloadSchedulingStateFromPreferences();

  final nowFn = now ?? DateTime.now;
  final fetch = fetchEvents ??
      (DateTime start, DateTime end) =>
          fetchMeetingsUncached(appState, start, end);
  final currentTime = nowFn();
  final offset = deviceUtcOffset ?? currentTime.timeZoneOffset;

  final today = midnight(currentTime);
  // docs/TODO.md T-71: only the ring checkpoint may treat today as concluded.
  // For FR-17's recovery and a settings change, today has NOT rung yet: it
  // must stay inside the window (FR-11: revisable until it actually rings) and
  // must not be counted by FR-9 ("heutiger Tag zählt nicht mit").
  final lastConcludedDay =
      todayAlreadyRang ? today : dayMarker(today, -1);
  final windowStart = dayMarker(lastConcludedDay, 1);
  final window = List.generate(7, (i) => dayMarker(windowStart, i));

  // docs/TODO.md T-75: the day-advance progress marker, deliberately NOT
  // `lastReplanDate` (which only answers FR-17's "did a checkpoint already run
  // today?"). Sharing one field let a harmless early-morning recovery replan
  // consume the marker without advancing it, so the real ring later that same
  // day found nothing to process - the day was lost, FR-9 under-counted and
  // FR-12 never reported. See test/replan_test.dart, group "T-75".
  final lastProcessedDay = appState.lastProcessedConcludedDay;
  final firstUnprocessedDay = lastProcessedDay == null
      ? lastConcludedDay
      : dayMarker(midnight(lastProcessedDay), 1);
  final needsDayAdvance = !firstUnprocessedDay.isAfter(lastConcludedDay);

  final fetchStart = needsDayAdvance ? firstUnprocessedDay : windowStart;
  final allEvents = await fetch(fetchStart, dayMarker(windowStart, 7));

  final durationToWakeUp = durationFromTimeOfDay(appState.durationToWakeUp);
  final durationToGetReady = durationFromTimeOfDay(appState.durationToGetReady);

  var possiblyMissedAppointment = false;
  var daysProcessed = 0;
  var daysWithHardFloor = 0;
  final gapCounterBefore = appState.gapDayCounter;

  // FR-9 says "heutiger Tag zählt nicht mit" (today doesn't count yet, since
  // it hasn't concluded) - but from THIS function's own perspective, `ringDay`
  // (the day whose alarm just rang) HAS just concluded, right now: this is
  // the one and only moment its hardFloor status is ever known/processed (see
  // computeWeekPlan's own doc comment: gapDayCounter must already reflect
  // every concluded day up to today BEFORE that call, and "today" there means
  // the day the NEW window starts from, i.e. the day after `ringDay`). So
  // `ringDay` itself is correctly included as the loop's last iteration, not
  // deferred to some later "catch-up" pass that doesn't otherwise exist.
  if (needsDayAdvance) {
    var day = firstUnprocessedDay;
    while (!day.isAfter(lastConcludedDay)) {
      final hf = hardFloor(
        day: day,
        allEvents: allEvents,
        deviceUtcOffset: offset,
        durationToWakeUp: durationToWakeUp,
        durationToGetReady: durationToGetReady,
      );
      appState.gapDayCounter = updateGapDayCounter(
        previousCounter: appState.gapDayCounter,
        dayHadRealHardFloor: hf != null,
      );
      daysProcessed++;
      if (hf != null) daysWithHardFloor++;

      final storedValue =
          instantFromStored(appState.pendingDayValues[isoDate(day)]);
      // docs/TODO.md T-74c: on the very first replan ever there is no history
      // at all, so "an appointment your last alarm may have missed" would be a
      // false positive on a fresh install. Keyed on the progress marker (T-75),
      // i.e. "has any day ever been processed", not on "did a checkpoint run
      // today" - the latter is true even on the first run of the day.
      if (lastProcessedDay != null &&
          hf != null &&
          (storedValue == null || hf.isBefore(storedValue))) {
        // FR-12: a real appointment surfaced too late to have been honored
        // for a day that already rang.
        possiblyMissedAppointment = true;
      }

      day = dayMarker(day, 1);
    }
  }

  // docs/TODO.md T-89: `daysProcessed == 0` an einem Tag, an dem der Wecker
  // geklingelt hat, IST die Signatur von T-75 (ein verlorener Tag). Genau
  // dieser Befund liess sich vorher nur durch einen handgeschriebenen
  // Probe-Test nachweisen.
  Diag.dayAdvance(
    needsDayAdvance: needsDayAdvance,
    hadProgressMarker: lastProcessedDay != null,
    daysProcessed: daysProcessed,
    daysWithHardFloor: daysWithHardFloor,
    gapCounterBefore: gapCounterBefore,
    gapCounterAfter: appState.gapDayCounter,
    missedAppointmentFlagged: possiblyMissedAppointment,
  );

  final lastEffectiveWakeTime =
      instantFromStored(appState.pendingDayValues[isoDate(lastConcludedDay)]);

  final result = computeWeekPlan(
    window: window,
    lastEffectiveWakeTime: lastEffectiveWakeTime,
    allEvents: allEvents,
    deviceUtcOffset: offset,
    durationToWakeUp: durationToWakeUp,
    durationToGetReady: durationToGetReady,
    wunschzeit: appState.wunschzeit,
    maxDailyDelta: appState.maxDailyDelta,
    gapDayCounter: appState.gapDayCounter,
  );

  // Merged, not replaced - and the retention below is **load-bearing**, not
  // laziness: the window starts the day after `lastConcludedDay`, so today's
  // own entry (on the recovery path: today has not rung yet) only survives
  // because entries outside the window are kept. FR-18's alarm sync schedules
  // every still-future value in this map, so dropping it would delete today's
  // not-yet-rung alarm on the next checkpoint (e.g. FR-17 after an
  // early-morning reboot) and the user would oversleep. See
  // test/apply_alarms_test.dart's "heutiger, noch nicht geklingelter Alarm
  // bleibt erhalten" regression test before changing this.
  //
  // Kept bounded all the same (docs/TODO.md T-82): everything strictly before
  // yesterday is unreachable - `lastEffectiveWakeTime` only ever reads
  // `lastConcludedDay`, and FR-18 only ever schedules future values - so
  // without a cut-off the map just grew by one entry per day forever, in a
  // JSON string that every replan decodes, copies and re-encodes. Yesterday
  // is kept as the margin that makes a recovery checkpoint (whose
  // `lastConcludedDay` *is* yesterday) safe.
  final oldestKeptDay = isoDate(dayMarker(lastConcludedDay, -1));
  bool worthKeeping(String day) => day.compareTo(oldestKeptDay) >= 0;

  // FR-11, zweite Haelfte: "Erst der tatsaechlich ausgeloeste Wert ist fuer
  // immer fix" - und "fuer immer" schliesst den Rest desselben Tages ein
  // (docs/TODO.md T-106).
  //
  // Nur der Ring setzt `todayAlreadyRang`. Fuer `settingsChanged` und
  // `manualSync` beginnt das Fenster deshalb wieder bei HEUTE, auch wenn heute
  // vor zehn Minuten geklingelt hat - und der Merge unten schrieb dann den
  // bereits ausgeloesten Wert neu. Folgen: ein zweiter Alarm am selben Morgen
  // (FR-18 plant jeden noch zukuenftigen Wert), und - schwerer - unter dem
  // Klingeltag steht danach ein Wert, der nie geklingelt hat. Genau den liest
  // der naechste Checkpoint als `lastEffectiveWakeTime` (FR-3: "immer der
  // Eintrag in `pendingDayValues` fuer den zuletzt abgeschlossenen Tag"), also
  // haengt die ganze Folgewoche an einem erfundenen Anker.
  //
  // Abgeschlossen ist ein Tag genau dann, wenn er nicht nach dem
  // Fortschrittsmarker liegt - nach dessen Fortschreibung durch DIESEN Lauf,
  // die erst weiter unten passiert.
  final concludedThrough = needsDayAdvance
      ? lastConcludedDay
      : (lastProcessedDay == null ? null : midnight(lastProcessedDay));
  bool alreadyConcluded(DateTime day) =>
      concludedThrough != null && !day.isAfter(concludedThrough);

  final mergedValues = <String, int?>{
    for (final entry in appState.pendingDayValues.entries)
      if (worthKeeping(entry.key)) entry.key: entry.value,
  };
  final prunedCount = appState.pendingDayValues.length - mergedValues.length;
  for (final day in window) {
    // Der Tag laeuft in `computeWeekPlan` weiter mit (er traegt die Kurve) -
    // nur sein AUFGEZEICHNETER Wert bleibt stehen. Das Fenster zu verkuerzen
    // waere falsch: dann verlöre die Rechnung ihren Ankertag.
    if (alreadyConcluded(day)) continue;
    mergedValues[isoDate(day)] = toStored(result.valuesByDay[day]);
  }
  appState.pendingDayValues = mergedValues;

  // FR-16: derselbe Merge wie oben (samt derselben Grenze), damit Checkpoint 2
  // auch für den heutigen (noch nicht geklingelten) Tag weiß, ob dessen Wert
  // instant- oder ziffern-verankert ist.
  final mergedAnchors = <String, bool>{
    for (final entry in appState.pendingDayInstantAnchored.entries)
      if (worthKeeping(entry.key)) entry.key: entry.value,
  };
  for (final day in window) {
    // Dieselbe FR-11-Sperre wie oben (T-106): gehoert der Wert eines Tages
    // nicht mehr uns, gehoert auch seine Verankerungs-Angabe nicht mehr uns.
    // Sonst stuende unter dem Klingeltag ein Wert mit der Verankerung eines
    // anderen - und FR-16s Checkpoint 2 wuerde ihn falsch (oder gar nicht)
    // umdeuten.
    if (alreadyConcluded(day)) continue;
    if (result.valuesByDay[day] == null) {
      mergedAnchors.remove(isoDate(day));
    } else {
      mergedAnchors[isoDate(day)] =
          result.instantAnchoredDays.contains(day);
    }
  }
  appState.pendingDayInstantAnchored = mergedAnchors;

  // `windowDayCount != distinctDayKeys` ist die Signatur von T-74d/T-76: zwei
  // Fenstertage sind auf denselben Tagesschluessel kollidiert.
  Diag.weekPlanComputed(
    todayAlreadyRang: todayAlreadyRang,
    windowDayCount: window.length,
    distinctDayKeys: window.map(isoDate).toSet().length,
    plannedDays: result.valuesByDay.values.whereType<DateTime>().length,
    nullDays: result.valuesByDay.values.where((v) => v == null).length,
    instantAnchoredDays: result.instantAnchoredDays.length,
    overrunFlag: result.overrunNotificationNeeded,
    safetyValveFlag: result.safetyValveTriggered,
    hasWunschzeit: appState.wunschzeit != null,
    maxStep: bucketMinutes(_maxStepMinutes(result.valuesByDay, window)),
    storedEntriesTotal: mergedValues.length,
    storedEntriesPruned: prunedCount,
  );

  appState.lastReplanDate = today;
  // Only ever forward (docs/TODO.md T-75): a recovery replan's own
  // `lastConcludedDay` is yesterday, so assigning unconditionally would move
  // the marker *backwards* after a ring checkpoint already concluded today and
  // let today be counted twice.
  if (needsDayAdvance) {
    appState.lastProcessedConcludedDay = lastConcludedDay;
  }

  // docs/TODO.md T-63: turn the computed week into actual alarms. Called here,
  // inside replan() itself, rather than from each checkpoint separately - that
  // way no code path can compute a plan and forget to apply it, which is
  // exactly how the whole engine ended up functionally inert before.
  await applyPlannedAlarms(appState, now: nowFn);

  return ReplanResult(
    overrunNotificationNeeded: result.overrunNotificationNeeded,
    safetyValveTriggered: result.safetyValveTriggered,
    possiblyMissedAppointment: possiblyMissedAppointment,
  );
}

// docs/TODO.md T-87: runAlarmRingCheckpoint(), onAppForegroundCheckpoint() und
// runForegroundCheckpointSafely() standen hier. Sie sind in den einen
// Einstiegspunkt runSchedulingCheckpoint() (checkpoint.dart) aufgegangen -
// dieselbe Sequenz, aber genau einmal formuliert, serialisiert (T-77) und
// vollständig (T-80). Was sie unterschied, ist dort CheckpointTrigger.
//
// Diese Datei ist damit wieder auf ihre eigentliche Aufgabe reduziert: WAS
// geplant wird (FR-8 und FR-16s Checkpoint 2), nicht WANN und WORAUFHIN.

/// FR-16 Checkpoint 2 (docs/scheduling-v2-spec.md): fires at the computed
/// sleep-time notification (Phase 5 step 22's `onNotificationCreatedMethod`),
/// which runs in its own background isolate with **no `AppState`/`Provider`
/// access at all** - unlike [runAlarmRingCheckpoint], this reads/writes
/// `lastCheckedUtcOffset` **directly via `SharedPreferences`**, using the
/// exact same key `AppState.lastCheckedUtcOffset` itself persists to
/// (`lastCheckedUtcOffsetMinutes`), so a later, normal `AppState` load in the
/// main isolate picks up whatever this checkpoint last wrote.
///
/// Per FR-16's own text, Checkpoint 2 "löst ausschließlich den
/// Zeitzonen-Vergleich aus, keine Neuplanung, keinen Kalenderzugriff" - it
/// never calls [replan] and never reads the calendar. What it *does* do on a
/// detected change is FR-16's second half, applied to the still-pending days:
///
/// - **wall-clock-anchored** values (`wunschzeit`/curve) keep their **local
///   digits** - the alarm-clock convention, "7:00 stays 7:00, now in the new
///   zone" - via [reinterpretForNewOffset];
/// - **instant-anchored** values (taken straight from a real `hardFloor`) keep
///   their **instant**: the appointment does not move, only its local display
///   does (FR-16, "Instant-basierte Werte: unverändert").
///
/// Which is which cannot be re-derived here without calendar access, so
/// `computeWeekPlan` records it per day and [replan] persists it next to the
/// values (`pendingDayInstantAnchored`, see `AppState`). Days that already lie
/// in the past are left untouched (FR-11: the value that actually rang is
/// fixed).
///
/// Known limitation, inherent to FR-16's own design: this corrects the stored
/// plan, not the alarms already handed to the platform - FR-16 explicitly
/// defers "die vollständige Neuberechnung" to the next regular planning run,
/// so an alarm that fires between the offset change and the next
/// replan/[applyPlannedAlarms] still uses the pre-change moment.
Future<void> runTimezoneCheckpoint2({
  Duration Function()? readOffset,
  SharedPreferences? prefs,
  DateTime Function()? now,
}) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  final offset = (readOffset ?? () => DateTime.now().timeZoneOffset)();
  final previousMinutes = p.getInt('lastCheckedUtcOffsetMinutes');
  final previousOffset =
      previousMinutes == null ? null : Duration(minutes: previousMinutes);

  if (previousOffset != null && previousOffset != offset) {
    try {
      final rawValues = p.getString('pendingDayValues');
      if (rawValues != null) {
        final values = (jsonDecode(rawValues) as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value as int?));
        final rawAnchored = p.getString('pendingDayInstantAnchored');
        final anchored = rawAnchored == null
            ? const <String, bool>{}
            : (jsonDecode(rawAnchored) as Map<String, dynamic>)
                .map((key, value) => MapEntry(key, value as bool));
        final nowValue = (now ?? DateTime.now)();

        var changed = false;
        var reinterpreted = 0;
        final updated = Map<String, int?>.from(values);
        values.forEach((day, millis) {
          if (millis == null) return;
          if (anchored[day] == true) return; // instant-anchored: leave alone
          final value = instantFromStored(millis)!;
          if (!value.isAfter(nowValue)) return; // already rung (FR-11)
          updated[day] = toStored(reinterpretForNewOffset(
            value: value,
            oldOffset: previousOffset,
            newOffset: offset,
          ));
          reinterpreted++;
          changed = true;
        });

        if (changed) {
          await p.setString('pendingDayValues', jsonEncode(updated));
        }

        // docs/TODO.md T-62/T-89: taucht dieses Ereignis im Export auf, ist
        // belegt, dass die stille Notification den Callback wirklich
        // ausgeloest hat - die Frage, die T-62 seit Phase 5 offen haelt.
        //
        // `Diag.init` steht bewusst NICHT hier, sondern am Einstiegspunkt des
        // Isolates (`onNotificationCreatedMethod`, lib/utils/notifications.dart):
        // init setzt globalen Zustand (Prefs-Handle, Isolate-Kennung), und
        // diese Funktion wird auch direkt aus Tests im Haupt-Isolate gerufen -
        // dort wuerde sie den Logger des Haupt-Isolates umschalten.
        Diag.timezoneCheck(
          offsetChanged: true,
          shape: bucketOffsetChange(previousOffset, offset),
          valuesConsidered: values.length,
          valuesReinterpreted: reinterpreted,
        );
        await Diag.flush();
      }
    } catch (e) {
      // Never let this break the checkpoint's primary job (persisting the
      // offset) - a corrupted/incompatible stored map must not leave the
      // offset stale, or the change would be re-detected forever.
      debugPrint(
          "=====runTimezoneCheckpoint2: reinterpreting pendingDayValues failed: ${e.runtimeType}");
    }
  }

  await p.setInt('lastCheckedUtcOffsetMinutes', offset.inMinutes);
}

/// Der groesste Tagesschritt im Plan, in Minuten - Eingabe fuer das
/// Bucket-Feld `maxStepBucket` (docs/TODO.md T-89).
///
/// Es geht ausschliesslich um die **Differenz** zweier Planwerte, nie um einen
/// Zeitpunkt selbst: eine Historie von Weckzeitpunkten waere ein Schlafmuster.
/// Der nominale Tagesabstand wird herausgerechnet, damit uebrig bleibt, was
/// FR-6 begrenzt - die Verschiebung der Weckzeit pro Tag. Uebersprungene Tage
/// (Lueckentage ohne Wert) werden dabei mitgezaehlt, sonst waere der Schritt um
/// ein Vielfaches von 24 Stunden zu gross.
int _maxStepMinutes(
    Map<DateTime, DateTime?> valuesByDay, List<DateTime> window) {
  const minutesPerDay = 24 * 60;
  var worst = 0;
  DateTime? previousValue;
  DateTime? previousDay;

  for (final day in window) {
    final value = valuesByDay[day];
    if (value == null) continue;
    if (previousValue != null && previousDay != null) {
      final spannedDays = dayDistance(day, previousDay);
      final step = value.difference(previousValue).inMinutes -
          spannedDays * minutesPerDay;
      if (step.abs() > worst.abs()) worst = step;
    }
    previousValue = value;
    previousDay = day;
  }
  return worst;
}
