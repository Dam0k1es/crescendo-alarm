import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:wakeywakey/models/alarms/manual_alarm.dart';

// FR-21 (docs/scheduling-v2-spec.md), "Manual alarms" - docs/TODO.md T-03.
//
// A separate, plugin-free and AppState-free file with injectable platform
// calls, the same split as `snooze.dart` and `planAlarmSync`/
// `applyPlannedAlarms`: the decision "which moment does this alarm go back to,
// and what has to happen at the platform" is arithmetic, and it must be
// testable without a device - `Alarm.set` has no channel in a unit test.
//
// Deliberately NOT a test seam inside AppState: a switch that only exists for
// tests but ships in the release binary is the defect docs/TODO.md T-16
// describes.

/// The next moment a manual alarm's bare [time] refers to.
///
/// Today at that time if that is still after [now], otherwise tomorrow. This
/// is the resolution `AppState.addAlarm` uses when an alarm is created, and
/// re-arming has to match it: switching an alarm off and on again must not
/// land on a different day than creating it anew with the same time would.
DateTime nextManualOccurrence(TimeOfDay time, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return today.isAfter(now) ? today : today.add(const Duration(days: 1));
}

/// Makes the alarm-list toggle of a [ManualAlarm] real (FR-21).
///
/// Returns `true` when the platform accepted the change. On `false` the flag
/// on [alarm] is left **untouched**, and that is the point: if cancelling
/// fails, the alarm will ring, and a switch claiming otherwise would be the
/// same broken promise T-03 was - only better hidden. The caller shows the
/// unchanged state, so the user sees that it did not take.
///
/// The platform call comes first, the flag second, for the same reason
/// `snoozeRingingAlarm` arms before it stops: the recorded state must never
/// describe something the device is not actually doing.
Future<bool> applyManualAlarmEnabled({
  required ManualAlarm alarm,
  required bool enabled,
  required DateTime now,
  required Future<void> Function(ManualAlarm alarm, DateTime at) armAlarm,
  required Future<void> Function(int id) stopAlarm,
}) async {
  try {
    if (enabled) {
      await armAlarm(alarm, nextManualOccurrence(alarm.time, now));
    } else {
      await stopAlarm(alarm.id);
    }
  } catch (e) {
    debugPrint(
        "=====applyManualAlarmEnabled: platform call failed: ${e.runtimeType}");
    return false;
  }

  alarm.enabled = enabled;
  return true;
}
