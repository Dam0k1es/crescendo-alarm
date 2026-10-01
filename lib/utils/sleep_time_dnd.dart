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

// docs/TODO.md T-198: the Dart half of the sleep-time Do Not Disturb
// trigger. Read that entry before changing anything here - this feature
// failed on a real phone once already (T-184 ... T-191, removed in T-197),
// with every unit test green.
//
// Division of labour, and why it is this way round:
//
// - Dart only ever COMPUTES the window [next alarm - Sleep Goal, next alarm)
//   and hands it to the native side. It never switches Do Not Disturb
//   itself, and nothing here is hung on an awesome_notifications callback:
//   T-198's H1 finding (AndroidAwnCore 0.12.1, read from its bytecode) is
//   that `onNotificationCreatedMethod` fires when a notification is
//   SCHEDULED, and that a title/body-less scheduled notification produces no
//   Dart callback at all when it comes due. The removed implementation
//   activated Do Not Disturb from exactly that callback - which is both of
//   T-197's device symptoms.
// - The native side (android/.../SleepTimeDnd.kt, SleepTimeDndPolicy.kt,
//   SleepTimeDndReceiver.kt) arms two exact AlarmManager alarms, one at the
//   window's start and one at its end, and switches Do Not Disturb from its
//   own BroadcastReceiver when they fire - with no Flutter engine involved.
//   That is the only way the end can be "exactly the very first ring" when
//   the app process is dead overnight (H3: the `alarm` plugin drops its
//   `alarmRang` callback when no engine is attached), and the end alarm is
//   armed with the same `setExactAndAllowWhileIdle(RTC_WAKEUP, ...)` call the
//   `alarm` plugin uses for the ring itself, at the same whole-minute instant.
//
// The window is re-computed and pushed at the bedtime reminder's own call
// sites (R2: "Die Zeitplanung ist bzgl des Starts daher zu übernehmen" -
// its scheduling is therefore to be adopted for the start) -
// the end of every scheduling checkpoint and every handled alarm - and
// additionally after every real alarm arm/cancel, at cold start, and when
// the setting changes (see AppState.refreshSleepTimeDnd for why a trigger
// that ACTS needs more call sites than a notification that only reminds).

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/next_wake_up.dart';
import 'package:crescendo_alarm/models/scheduling/stored_values.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/utils.dart';

/// Shared with `SleepTimeDnd.CHANNEL` in the Kotlin side -
/// test/sleep_time_dnd_platform_contract_test.dart keeps the two equal.
const String sleepTimeDndChannelName =
    'com.crescendoalarm.crescendoalarm/sleep_time_dnd';

const MethodChannel _channel = MethodChannel(sleepTimeDndChannelName);

/// Sleep time: from [start] (inclusive) to [end] (exclusive). Both are
/// local wall-clock `DateTime`s on the same whole-minute boundary the
/// `alarm` plugin rings at ([alarmPlatformTime]).
typedef SleepTimeWindow = ({DateTime start, DateTime end});

/// The sleep-time window for the Do Not Disturb trigger, or `null` when
/// there is none (no alarm ahead, or a Sleep Goal of 00:00).
///
/// "The next alarm" is [nextWakeUpTime] - the same function the bedtime
/// reminder uses (R2) - over two inputs narrowed to alarms that will
/// actually ring and that the user has not excluded:
///
/// - planned days switched off in the alarm list ([disabledDays], FR-21)
///   are left out: nothing rings on them, so they cannot be "the very first
///   ring" that ends sleep time (the reminder, unchanged, still counts them);
/// - manual alarms with [ManualAlarm.excludeFromSleepTime] are left out (R5).
///   `nextWakeUpTime` already ignores switched-off manual alarms.
///
/// Planned values are compared at the whole minute the ring is armed for
/// ([alarmPlatformTime]), not at their raw instant: a value planned for
/// 06:30:42 rings at 06:30:00, and between those two moments it must
/// already count as rung - otherwise the window would end in the past and
/// the native side would clear it instead of arming the next night.
///
/// [start] is the next alarm minus [sleepGoal] - WITHOUT the reminder's own
/// lead time, which only moves the notification earlier. A start already in
/// the past is returned as is; catching it up (T-110's "now + 2 minutes",
/// adopted from the reminder) happens on the native side, which is the only
/// side that knows whether Do Not Disturb is already on.
SleepTimeWindow? sleepTimeWindow({
  required Map<String, int?> pendingDayValues,
  required Set<String> disabledDays,
  required List<ManualAlarm> manualAlarms,
  required TimeOfDay sleepGoal,
  required DateTime now,
}) {
  final target = nextWakeUpTime(
    pendingDayValues: {
      for (final entry in pendingDayValues.entries)
        if (!disabledDays.contains(entry.key))
          entry.key: _ringMinuteMillis(entry.value),
    },
    manualAlarms: [
      for (final alarm in manualAlarms)
        if (!alarm.excludeFromSleepTime) alarm,
    ],
    now: now,
  );
  if (target == null) return null;

  // docs/TODO.md T-61: the same boundary as every other value leaving the
  // scheduling layer - read as local wall clock, truncated to the minute,
  // exactly as `AppState._setAlarm` arms the ring itself.
  final end = alarmPlatformTime(target);
  final start = alarmPlatformTime(target.subtract(durationFromTimeOfDay(sleepGoal)));
  if (!start.isBefore(end)) return null;
  return (start: start, end: end);
}

/// [stored] (a `pendingDayValues` entry) read as the local whole minute the
/// `alarm` plugin rings at, back in the same stored form.
int? _ringMinuteMillis(int? stored) {
  final local = localFromStored(stored);
  if (local == null) return null;
  return alarmPlatformTime(local).millisecondsSinceEpoch;
}

/// What the native side decided on a push. The codes are shared with
/// `SleepTimeDndPolicy.Code` in Kotlin (kept equal by
/// test/sleep_time_dnd_platform_contract_test.dart) and with
/// [DiagDndDecision].
enum SleepTimeDndDecision {
  /// The push never reached the native side (no Android, no channel).
  channelFailed(0),

  /// The feature is switched off; Do Not Disturb left if this app had
  /// switched it on.
  disabled(1),

  /// Switched on, but there is no alarm ahead to define sleep time.
  noWindow(2),

  /// Sleep time lies ahead - start and end alarms armed, nothing now.
  scheduled(3),

  /// Already inside sleep time and not yet active: activation follows in
  /// about two minutes (T-110's missed-bedtime handling, adopted).
  catchUp(4),

  /// Inside sleep time and already active - only the end is re-armed.
  alreadyActive(5),

  /// The window's end has passed - Do Not Disturb left if ours.
  ended(6),

  /// Inside sleep time, but the alarm is less than the catch-up delay away -
  /// nothing is activated for such a short stretch.
  tooLate(7),

  /// No longer produced (docs/TODO.md T-203 removed T-198's A1 rule, which
  /// skipped a window that began before the last ring). Kept so a report
  /// from a native side still on v1.4.0 - or code 10 in an exported log -
  /// still decodes.
  afterWakeUp(10);

  const SleepTimeDndDecision(this.code);
  final int code;

  static SleepTimeDndDecision fromCode(Object? code) =>
      SleepTimeDndDecision.values
          .where((d) => d.code == code)
          .firstOrNull ??
      SleepTimeDndDecision.channelFailed;
}

/// What a push reports back: the decision, plus what happened natively
/// since the previous push - booleans only, so it can be logged without a
/// single clock value (docs/TODO.md T-89).
class SleepTimeDndReport {
  const SleepTimeDndReport({
    required this.decision,
    this.startFired = false,
    this.endFired = false,
    this.applyFailed = false,
    this.accessMissing = false,
  });

  final SleepTimeDndDecision decision;

  /// The window's start alarm fired since the previous push.
  final bool startFired;

  /// The window's end alarm fired since the previous push.
  final bool endFired;

  /// A call to switch Do Not Disturb was refused since the previous push.
  final bool applyFailed;

  /// Android's "Do Not Disturb access" is not (or no longer) granted.
  final bool accessMissing;

  static const SleepTimeDndReport notDelivered =
      SleepTimeDndReport(decision: SleepTimeDndDecision.channelFailed);

  /// Worth a diagnostics record even when nothing else changed: these three
  /// are reset natively once reported, so each one is a single event.
  /// ([accessMissing] is a state, not an event - it stays set on every push
  /// until access is granted again, so it is de-duplicated like [decision].)
  bool get eventful => startFired || endFired || applyFailed;
}

typedef PushSleepTimeWindow = Future<SleepTimeDndReport> Function({
  required bool enabled,
  required SleepTimeWindow? window,
});

/// Hands the feature state and the current window to the native side.
///
/// An injectable seam, the same shape as `mirrorDirectBootFallback`: there
/// is no native implementation on the Linux dev loop or in `flutter test`,
/// where the call fails and [SleepTimeDndReport.notDelivered] comes back.
PushSleepTimeWindow pushSleepTimeWindow = defaultPushSleepTimeWindow;

Future<SleepTimeDndReport> defaultPushSleepTimeWindow({
  required bool enabled,
  required SleepTimeWindow? window,
}) async {
  try {
    final result =
        await _channel.invokeMapMethod<String, Object?>('setWindow', {
      'enabled': enabled,
      // Absolute instants: AlarmManager's RTC clock is epoch-based, so a
      // time zone change overnight moves neither the ring nor the window.
      'startMillis': window?.start.millisecondsSinceEpoch,
      'endMillis': window?.end.millisecondsSinceEpoch,
    });
    if (result == null) return SleepTimeDndReport.notDelivered;
    return SleepTimeDndReport(
      decision: SleepTimeDndDecision.fromCode(result['decision']),
      startFired: result['startFired'] == true,
      endFired: result['endFired'] == true,
      applyFailed: result['applyFailed'] == true,
      accessMissing: result['accessMissing'] == true,
    );
  } catch (e) {
    // MissingPluginException off Android, or a plain StateError in the
    // `package:test` suites that have no Flutter binding at all - either
    // way there is nothing to arm, and this must never surface as a failure
    // of whatever arm/cancel or checkpoint triggered it.
    return SleepTimeDndReport.notDelivered;
  }
}

/// One-shot cleanup of the removed v1.3.0 Do Not Disturb feature's leftover
/// (docs/TODO.md T-197): the native side ends it on API 35+ only, where it
/// can be nothing but this app's own mode. Called by AppState when it finds
/// that feature's old preference keys. An injectable seam like
/// [pushSleepTimeWindow].
Future<void> Function() clearLegacyDoNotDisturb = defaultClearLegacyDoNotDisturb;

Future<void> defaultClearLegacyDoNotDisturb() async {
  try {
    await _channel.invokeMethod<bool>('clearLegacy');
  } catch (e) {
    // No native side (Linux dev loop, flutter test) - nothing to clean.
  }
}

/// The phone's current, effective interruption filter
/// (`NotificationManager.getCurrentInterruptionFilter()`: 1 = all, 2 =
/// priority, 3 = none, 4 = alarms), or `null` off Android. Read-only; used
/// by integration_test/sleep_time_dnd_test.dart to observe the real
/// platform state rather than a fake.
Future<int?> readCurrentInterruptionFilter() async {
  try {
    return await _channel.invokeMethod<int>('currentInterruptionFilter');
  } catch (e) {
    return null;
  }
}

/// Whether Android's "Do Not Disturb access" is granted to this app, as the
/// native side sees it (`NotificationManager.isNotificationPolicyAccessGranted`).
Future<bool> readDndAccessGranted() async {
  try {
    return await _channel.invokeMethod<bool>('isAccessGranted') ?? false;
  } catch (e) {
    return false;
  }
}

/// Translates the decision into the logger's own stable code (the logger
/// keeps its own enum, like `DiagTrigger` - it must not import this layer).
DiagDndDecision diagDndDecisionOf(SleepTimeDndDecision decision) =>
    switch (decision) {
      SleepTimeDndDecision.channelFailed => DiagDndDecision.channelFailed,
      SleepTimeDndDecision.disabled => DiagDndDecision.disabled,
      SleepTimeDndDecision.noWindow => DiagDndDecision.noWindow,
      SleepTimeDndDecision.scheduled => DiagDndDecision.scheduled,
      SleepTimeDndDecision.catchUp => DiagDndDecision.catchUp,
      SleepTimeDndDecision.alreadyActive => DiagDndDecision.alreadyActive,
      SleepTimeDndDecision.ended => DiagDndDecision.ended,
      SleepTimeDndDecision.tooLate => DiagDndDecision.tooLate,
      SleepTimeDndDecision.afterWakeUp => DiagDndDecision.afterWakeUp,
    };
