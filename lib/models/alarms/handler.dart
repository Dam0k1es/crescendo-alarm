// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/screens/alarms/screen_active_alarm.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/sleep_reminder.dart';
import 'package:crescendo_alarm/utils/utils.dart';

/// Whether an alarm's scheduled [eventDateTime] is already in the past
/// relative to [now]. Compares full DateTimes (not just day/hour/minute) so
/// a stale alarm from a previous day/month/year is correctly detected too;
/// both are truncated to minute precision, as the alarm plugin may trigger
/// an alarm a few milliseconds before or after the scheduled time.
bool isAlarmStale(DateTime eventDateTime, DateTime now) {
  final eventMinute = DateTime(eventDateTime.year, eventDateTime.month,
      eventDateTime.day, eventDateTime.hour, eventDateTime.minute);
  final nowMinute =
      DateTime(now.year, now.month, now.day, now.hour, now.minute);
  return eventMinute.isBefore(nowMinute);
}

class Handler {
  final BuildContext _context;
  late final AppState _appState;
  final Future<ReplanResult?> Function(AppState appState) _runCheckpoint;

  /// Injectable purely for testability - see
  /// test/handler_overlay_retry_test.dart, which needs to control the pause
  /// between retries without a real test waiting on real wall-clock time.
  final Future<void> Function(Duration duration) _sleep;

  /// docs/TODO.md T-38 (maintainer request): showing the ringing overlay is
  /// retried this many times, [overlayRetryDelay] apart, before the 3-second
  /// fallback below gives up and silently stops the alarm. A single failed
  /// attempt used to give up immediately - but `context.mounted` can flip
  /// back to true moments later (e.g. the app is still finishing its own
  /// startup right as the alarm fires), and retrying costs nothing an alarm
  /// clock's whole purpose doesn't already risk more of by staying silent.
  @visibleForTesting
  static const int maxOverlayAttempts = 5;

  /// Also the fallback's own final wait before [Alarm.stopAll] - see
  /// [handleAlarm]'s doc comment on why the two share one constant.
  @visibleForTesting
  static const Duration overlayRetryDelay = Duration(seconds: 3);

  /// [runCheckpoint] is injectable (defaults to the real ring checkpoint)
  /// purely for testability - see test/handler_replan_wiring_test.dart's
  /// regression test, which needs full control over when/whether it completes.
  Handler(this._context,
      {Future<ReplanResult?> Function(AppState)? runCheckpoint,
      Future<void> Function(Duration)? sleep})
      : _runCheckpoint = runCheckpoint ?? _ringCheckpoint,
        _sleep = sleep ?? Future.delayed {
    _appState = Provider.of<AppState>(_context, listen: false);
  }

  /// FR-8: the actual ring is scheduling-v2's daily replanning trigger -
  /// "feuert immer", regardless of how the rest of [handleAlarm] resolves
  /// (dismissed via overlay, via the 3s-timeout fallback, whatever). Fired
  /// via `unawaited` and wrapped in its own try/catch so a slow or failing
  /// checkpoint (a real calendar-plugin call) can never delay or break
  /// showing the alarm overlay / the 3s-fallback stop-all below - both of
  /// those must keep working exactly as before regardless of this call's
  /// outcome (docs/scheduling-v2-spec.md, Phase 5 step 19's regression test).
  void _fireReplanCheckpoint(AlarmSettings event) {
    // docs/TODO.md T-73: only a ringing ScheduledAlarm may advance the
    // ScheduledAlarm chain. Alarm.ringing fires for every alarm, and letting a
    // ManualAlarm drive it would count today as concluded (FR-9), freeze
    // today's not-yet-rung scheduled value as the anchor, and suppress FR-17
    // for the rest of the day - FR-15 forbids manual alarms influencing this
    // chain's state.
    final ringing = _appState.getAlarm(event.id);
    // docs/TODO.md T-89: the alarm type goes in as a type code, never as a
    // name - and with no timestamp at all. A history of exact wake instants
    // would be a sleep pattern, and thus identifying with no name at all.
    Diag.alarmRang(
      alarmType: ringing.runtimeType,
      knownToAppState: ringing != null,
      stale: isAlarmStale(event.dateTime, DateTime.now()),
      deactivationCodeSet: _appState.deactivationCode != null,
      checkpointFired: ringing is ScheduledAlarm,
    );
    if (ringing is! ScheduledAlarm) {
      debugPrint(
          "=====handleAlarm: ringing alarm ${event.id} is not a ScheduledAlarm - no replan checkpoint");
      return;
    }
    unawaited(_runReplanCheckpointSafely());
  }

  /// docs/TODO.md T-87: the whole sequence (offset, replan, FR-6/9/12
  /// reporting, bedtime reminder) now lives in one place, serialized against
  /// every other trigger - this is just the ring's way in.
  static Future<ReplanResult?> _ringCheckpoint(AppState appState) =>
      runSchedulingCheckpoint(appState,
          trigger: CheckpointTrigger.alarmRing);

  Future<void> _runReplanCheckpointSafely() async {
    try {
      await _runCheckpoint(_appState);
    } catch (e) {
      debugPrint("=====handleAlarm: ring checkpoint failed: ${e.runtimeType}");
    }
  }

  /// Tries [buildOverlay] up to [maxOverlayAttempts] times, [overlayRetryDelay]
  /// apart, stopping as soon as one succeeds. Returns whether an overlay is
  /// now showing.
  ///
  /// A single failed attempt used to give up immediately and fall straight
  /// through to the 3-second `Alarm.stopAll()` fallback - but `context.mounted`
  /// (the most common reason `showFullScreenOverlay` throws here) can flip
  /// back to true moments later, e.g. the app is still finishing its own
  /// startup right as the alarm fires. [buildOverlay] is called fresh on each
  /// attempt rather than built once up front, so a transient failure never
  /// reuses a widget instance from a moment the tree may have already moved
  /// on from.
  Future<bool> _showOverlayWithRetries(Widget Function() buildOverlay) async {
    for (var attempt = 1; attempt <= maxOverlayAttempts; attempt++) {
      try {
        if (!_context.mounted) {
          throw StateError('Context is no longer mounted');
        }
        showFullScreenOverlay(_context, buildOverlay());
        return true;
      } catch (e) {
        debugPrint(
            "=====handleAlarm: attempt $attempt/$maxOverlayAttempts to show "
            "the overlay failed: ${e.runtimeType}");
        if (attempt < maxOverlayAttempts) {
          await _sleep(overlayRetryDelay);
        }
      }
    }
    return false;
  }

  Future<void> handleAlarm(AlarmSettings event) async {
    _fireReplanCheckpoint(event);

    // docs/TODO.md T-89: a kDebugMode diagnostic block used to sit here,
    // creating two real notifications with alarm type, wake time, and alarm
    // id. They were only guarded by kDebugMode, not by main.dart's debugPrint
    // shutoff - so they landed in the notification shade and thus on the
    // LOCK SCREEN of every tester with a debug APK (ci.yml uploads exactly
    // one as an artifact for `dev`). A history of these is a sleep profile.
    // On top of that, it logged the exact wake time in plain text.
    //
    // The same diagnosis - and more - is now provided by the PII-free event
    // logger below (Diag.alarmRang): alarm type as a type code, no
    // timestamp, no id.

    bool stoppingAlarmPossible = true;

    try {
      // Check if the alarm is set in the past
      bool alarmSetBeforeNow = false;
      try {
        alarmSetBeforeNow = isAlarmStale(event.dateTime, DateTime.now());
      } catch (e) {
        debugPrint(
            "=====handleAlarm: Failed to check if alarm is set in the past: ${e.runtimeType}");
      }

      // If the event is in the past, stop it
      if (alarmSetBeforeNow) {
        debugPrint("=====handleAlarm: Stopping alarm that is set in the past");
        try {
          Alarm.stop(event.id);
        } catch (e) {
          debugPrint("=====handleAlarm: Failed to stop alarm: ${e.runtimeType}");
          stoppingAlarmPossible = false;
        }

        // Double check if alarm is still in the list of AlarmSettings
        try {
          List<AlarmSettings> alarmSettings = await Alarm.getAlarms();
          if (!alarmSettings.contains(event)) {
            return;
          }
        } catch (e) {
          debugPrint("=====handleAlarm: Failed to get alarms list: ${e.runtimeType}");
        }
      }

      // If the event is in the future or now, show either the default alarm overlay or the QR code scanner

      // Check if the deactivation code is set
      bool isDeactivationCodeSet = false;
      try {
        isDeactivationCodeSet = _appState.deactivationCode != null;
      } catch (e) {
        debugPrint(
            "=====handleAlarm: Failed to check if deactivation code is set: ${e.runtimeType}");
      }

      // FR-20: record the ORIGINAL wake instant before any screen appears.
      // Only here is it known at all - the screens only get an alarm id. It
      // carries the snooze budget, and `rememberSnoozeOrigin` does NOT
      // overwrite an existing entry: if an already-postponed call rings
      // again, the first instant stays in place - otherwise the budget
      // would restart from zero.
      try {
        _appState.rememberSnoozeOrigin(event.id, event.dateTime);
      } catch (e) {
        debugPrint(
            "=====handleAlarm: rememberSnoozeOrigin failed: ${e.runtimeType}");
      }

      // If the deactivation code is not set, show the alarm overlay; if it
      // is, show the QR code scanner instead.
      final overlayShown = await _showOverlayWithRetries(
        () => isDeactivationCodeSet
            ? QrScanner(alarmId: event.id)
            : ScreenAlarmActive(alarmId: event.id),
      );
      if (!overlayShown) stoppingAlarmPossible = false;
    } catch (e) {
      debugPrint("=====handleAlarm: Error handling alarm: ${e.runtimeType}");
    }

    // If the overlay still couldn't be shown after all retries above (or the
    // stale-alarm stop attempt itself failed), give it one more
    // overlayRetryDelay of grace, then silently stop everything rather than
    // leave an alarm ringing forever with nothing on screen to dismiss it.
    if (!stoppingAlarmPossible) {
      try {
        await _sleep(overlayRetryDelay);
        Alarm.stopAll();
      } catch (e) {
        debugPrint("=====handleAlarm: Failed to stop all alarms: ${e.runtimeType}");
      }
    }
  }

  /// Reschedules the sleep-time reminder after an alarm was handled, and -
  /// since docs/TODO.md T-14 - re-arms a repeating [ManualAlarm] for its
  /// next selected day.
  ///
  /// The sleep-reminder reschedule happens always, regardless of
  /// [AppState.reminderEnabled] (FR-16 "Voraussetzung",
  /// docs/scheduling-v2-spec.md): Checkpoint 2 needs a notification hook even
  /// when the visible reminder itself is disabled; `scheduleSleepReminder()`/
  /// `sleepReminderContent()` decide visible-vs-silent, not whether to
  /// schedule at all. Fire-and-forget (not awaited), matching this method's
  /// callers (qr_scanner.dart, screen_active_alarm.dart), none of which await
  /// it either.
  ///
  /// **Phase 6 (docs/TODO.md T-64):** this used to also call the old
  /// `Scheduler.scheduleAlarms()` behind `rescheduleOnAlarm` - which deletes
  /// every ScheduledAlarm first and then aborts without re-setting any of them
  /// whenever `appState.meetings` is empty (the normal state in a process the
  /// alarm itself started). A dismiss therefore left the user with **no alarms
  /// at all**; `test/handler_on_alarm_handled_test.dart` pins that down. There
  /// is nothing to replace it with here for `ScheduledAlarm`s: the ring
  /// already ran the full scheduling checkpoint via `handleAlarm()`'s
  /// `_fireReplanCheckpoint()`, which re-plans the week and applies it
  /// (FR-8/FR-18).
  ///
  /// **T-14: a `ManualAlarm`'s `repeatOnDays` promises a weekly recurrence,
  /// but the platform alarm underneath it is one-shot** - honouring
  /// `repeatOnDays` when first picking a day (`nextManualOccurrence`) only
  /// makes it fire once, on whichever selected day comes first. Making it a
  /// real, ongoing repeat means re-arming on every dismiss, and this is the
  /// one place every dismissal path (the Stop button, the QR gate, and
  /// T-147's auto-close) already funnels through. `ScheduledAlarm`s are
  /// deliberately excluded - that is FR-18's domain, and re-arming one here
  /// would be a second, conflicting scheduling path (the exact class of bug
  /// T-64 above already fixed once).
  ///
  /// [notifications] and [setManualAlarmEnabled] are both injectable
  /// (defaulting to the real [Notifications] and [AppState
  /// .setManualAlarmEnabled]) purely for testability - see
  /// test/sleep_reminder_always_scheduled_test.dart and
  /// test/handler_manual_alarm_rearm_test.dart, neither of which can reach
  /// the real `alarm` plugin from `flutter test`.
  static void onAlarmHandled(
    AppState appState,
    int alarmID, {
    Notifications? notifications,
    Future<bool> Function(ManualAlarm alarm, bool enabled)?
        setManualAlarmEnabled,
  }) {
    scheduleSleepReminder(appState, notifications: notifications);

    final alarm = appState.getAlarm(alarmID);
    if (alarm is ManualAlarm && alarm.enabled) {
      unawaited(
        (setManualAlarmEnabled ?? appState.setManualAlarmEnabled)(
          alarm,
          true,
        ),
      );
    }
  }
}
