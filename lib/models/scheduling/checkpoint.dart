// The one entry point for scheduling-v2 (docs/TODO.md T-87, fixes T-77
// and T-80).
//
// Previously there were five: replan(), runAlarmRingCheckpoint(),
// onAppForegroundCheckpoint(), runForegroundCheckpointSafely() and
// onSchedulingSettingsChanged(). They differed along four orthogonal
// dimensions - does the caller record the time zone offset? does today
// count as concluded? are FR-6/9/12 reported? is the bedtime notification
// replanned? are errors swallowed? - and every combination was assembled by
// hand somewhere. Exactly this matrix produced T-67 (reporting was missing
// on the recovery path), T-71 (today was wrongly treated as concluded) and
// T-80 (the reminder was missing from both checkpoints): the same bug three
// times in the same structure.
//
// Here the sequence exists exactly once, complete and serialized. What
// differs per trigger is exclusively [CheckpointTrigger] - and that lives as
// a table in [runSchedulingCheckpoint]'s doc comment, not implicitly across
// five call sites.
//
// Deliberately in its own file, not in replan.dart: the sequence needs
// sleep_reminder.dart, and that pulls an import cycle back to replan.dart
// (FR-16 checkpoint 2) via notifications.dart.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/models/scheduling/replan_notifications.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/sleep_reminder.dart';

/// What triggered the checkpoint. The only difference between the flows -
/// see the table in [runSchedulingCheckpoint].
enum CheckpointTrigger {
  /// FR-8/FR-16 checkpoint 1: an alarm just rang. The only trigger for which
  /// today counts as concluded (FR-11).
  alarmRing,

  /// FR-17: the app came to the foreground (cold start after reboot/force-quit,
  /// or a normal resume). Subject to FR-17's daily lock.
  appForeground,

  /// docs/TODO.md T-65: a setting that feeds into the computation has
  /// changed. Deliberately **not** subject to the daily lock - a change must
  /// take effect immediately.
  settingsChanged,

  /// The user pressed the sync button in the alarm list (Phase 6,
  /// docs/TODO.md T-64 - the old Scheduler used to run there). Behaves like
  /// [settingsChanged]; its own value so the table below and the debug
  /// output stay honest.
  manualSync,
}

/// Serializes every checkpoint against every other one (docs/TODO.md T-77).
///
/// Necessary because three of the four triggers are fire-and-forget
/// (`unawaited`) and FR-17's daily lock cannot protect against that: it reads
/// `lastReplanDate`, which is only written at the **end** of `replan()`. When
/// an alarm rings, Android brings the app forward via a full-screen intent,
/// so the resume trigger fires immediately too - the second checkpoint used
/// to start in the middle of the first one's calendar I/O. Consequence:
/// `gapDayCounter` incremented twice (FR-9's valve miscounts) and both
/// computed `toAdd` values against the same stale alarm list, i.e. duplicate
/// alarms on the same minute.
Future<void> _tail = Future<void>.value();

/// How many checkpoints are currently queued. Diagnostics only: a value > 0
/// at the start proves exactly the interleaving that T-77 was (a ring brings
/// the app forward via a full-screen intent, so resume fires immediately
/// too).
int _pending = 0;

Future<T> _serialized<T>(Future<T> Function() body) {
  final completer = Completer<T>();
  _pending++;
  _tail = _tail.then((_) async {
    try {
      completer.complete(await body());
    } catch (error, stack) {
      // The error goes to its own caller; the chain itself stays intact, so
      // a broken checkpoint doesn't block every following one.
      completer.completeError(error, stack);
    } finally {
      _pending--;
    }
  });
  return completer.future;
}

/// The complete response to a trigger, in fixed order:
///
/// 1. serialize (T-77),
/// 2. check FR-17's daily lock (only for [CheckpointTrigger.appForeground]),
/// 3. record the current time zone offset (FR-16),
/// 4. [replan] - including FR-18's alarm reconciliation, which `replan()`
///    itself triggers,
/// 5. report FR-6/FR-9/FR-12 ([reportReplanNotifications]),
/// 6. replan the bedtime notification ([scheduleSleepReminder], T-80).
///
/// | Trigger | today concluded (FR-11) | daily lock (FR-17) |
/// |---|---|---|
/// | `alarmRing` | yes | no |
/// | `appForeground` | no | yes |
/// | `settingsChanged` | no | no |
/// | `manualSync` | no | no |
///
/// Returns `null` if FR-17's daily lock kicked in (no I/O, nothing changed),
/// otherwise the result of the replan.
///
/// Rethrows if the replan fails - callers that can't handle that (UI paths)
/// use [runCheckpointSafely] instead.
Future<ReplanResult?> runSchedulingCheckpoint(
  AppState appState, {
  required CheckpointTrigger trigger,
  FetchEvents? fetchEvents,
  DateTime Function()? now,
  Duration? deviceUtcOffset,
  Notifications? notifications,
}) {
  // Measured before serialization, so the wait behind a running checkpoint
  // actually becomes visible at all.
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
      // FR-17: a second app open on the same day is a no-op. Read inside the
      // serialization, so the value doesn't come from a checkpoint running
      // in parallel that is about to write it anyway.
      //
      // The condition is **equality**, not "not before today" (docs/TODO.md
      // T-109). FR-17 literally says "If `lastReplanDate` ≠ today's calendar
      // date: immediately […] Otherwise: no additional checkpoint" - and a
      // `>=` would additionally swallow the case where the marker lies in
      // the FUTURE.
      //
      // It gets there with no action by the app at all: it's a device-local
      // digit date with no clamping, and a zone change across the date
      // boundary (Apia +13 → Pago Pago −11) or a backward correction of the
      // system clock makes the local date jump backward. Measured cases ran
      // up to ~48 local hours with not a single foreground checkpoint -
      // i.e. without the uncached calendar re-read that would repair a
      // stale plan. A ring repairs the marker as a side effect, but exactly
      // in FR-17's three gaps (reboot, force-quit, a ring that failed to
      // happen) there is none.
      //
      // Compared via `dayDistance`, not via `==` on two `DateTime`s: the
      // marker comes locally tagged from the preferences, `currentTime` can
      // be a `tz.TZDateTime`, and Dart's `==` requires the same `isUtc`
      // frame. That is this module's error class (T-61/T-76/T-83) -
      // `dayDistance` deliberately compares the date digits.
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

    // FR-16: record the checked offset regardless of whether anything
    // changed - otherwise checkpoint 2 would keep rediscovering the same
    // change forever. Deliberately before the replan, so a calendar error
    // doesn't leave the offset stale.
    appState.lastCheckedUtcOffset = offset;

    try {
      final result = await replan(
        appState,
        fetchEvents: fetchEvents,
        now: now,
        deviceUtcOffset: deviceUtcOffset,
        // FR-11: only the value that has actually been triggered is fixed
        // (docs/TODO.md T-71). For recovery and settings changes, today has
        // not rung yet, so it stays revisable and uncounted.
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
      // docs/TODO.md T-80: bedtime is derived from the freshly planned wake
      // instant, so it must run after the replan - and on EVERY trigger, not
      // just on dismiss and the reminder toggle. Otherwise FR-16's
      // checkpoint 2 fires at an instant with no relation to the plan.
      //
      // In the `finally`, so a failed calendar access doesn't take FR-16's
      // hook down with it: on a fresh install there is no bedtime
      // notification at all yet, and without one checkpoint 2 permanently
      // lacks its entry point. `scheduleSleepReminder` swallows its own
      // errors, so it cannot additionally break this path.
      await scheduleSleepReminder(appState, notifications: notifications);

      Diag.checkpointFinished(
        trigger: diagTriggerOf(trigger),
        outcome: outcome,
        took: bucketMillis(clock.elapsedMilliseconds),
      );
      // Persisted in a batch at the end of the sequence - so the ring path
      // itself gets no I/O latency from it.
      await Diag.flush();
    }
  });
}

/// [runSchedulingCheckpoint] for callers that must not fail: every UI and
/// lifecycle path (app start, resume, settings change). A genuine calendar
/// plugin outage must neither abort app start nor crash the UI that
/// triggered the change.
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

/// Translates the trigger into the stable diagnostic code.
///
/// The logger deliberately keeps its own enum: it must not import into the
/// scheduling layer, and the exported codes must stay stable even when a
/// trigger is added here.
DiagTrigger diagTriggerOf(CheckpointTrigger trigger) => switch (trigger) {
      CheckpointTrigger.alarmRing => DiagTrigger.alarmRing,
      CheckpointTrigger.appForeground => DiagTrigger.appForeground,
      CheckpointTrigger.settingsChanged => DiagTrigger.settingsChanged,
      CheckpointTrigger.manualSync => DiagTrigger.manualSync,
    };
