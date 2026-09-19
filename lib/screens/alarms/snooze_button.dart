// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/snooze.dart';
import 'package:wakeywakey/utils/utils.dart';

/// FR-20: the ring screen's snooze button.
///
/// Deliberately **one** widget for both screens (default overlay and QR
/// scanner) instead of two copies: the two only differ in how the alarm gets
/// *switched off*, not in how it gets postponed. Two copies would be two
/// places where the budget check could drift apart - exactly the bug class
/// this project already hit once with the five checkpoint entry points
/// (T-87).
///
/// It appears **only** while there is still budget left. Once it's used up,
/// there is no button - the alarm keeps ringing, and only the regular
/// switch-off remains (on the QR screen, that means a scan).
class SnoozeButton extends StatelessWidget {
  const SnoozeButton({
    super.key,
    required this.alarmId,
    this.onSnoozed,
    this.onBeforeSnooze,
    this.onSnoozeAttemptFailed,
  });

  final int alarmId;

  /// Runs after a successful postponement - the screens close themselves in
  /// response to it.
  final VoidCallback? onSnoozed;

  /// Runs synchronously the instant the button is pressed, before anything
  /// asynchronous happens.
  ///
  /// `snoozeRingingAlarm` stops the *old* alarm as its last step, which is
  /// the same `Alarm.stop()` a real dismissal uses - and therefore the same
  /// update to `Alarm.ringing` a `RingingWatch` on the calling screen also
  /// observes. Waiting for [onSnoozed] to mark "this was a snooze, not a
  /// real stop" is too late: by the time it runs, several `await` hops have
  /// already given `RingingWatch`'s own listener a chance to fire first (and
  /// in practice, does). Claiming that *before* the stop call even happens
  /// closes the race regardless of which side actually wins it.
  final VoidCallback? onBeforeSnooze;

  /// Runs when the attempt did not actually postpone anything (budget
  /// exhausted, or the platform refused) - undoes [onBeforeSnooze]'s claim,
  /// since nothing was stopped and the alarm is still ringing as before.
  final VoidCallback? onSnoozeAttemptFailed;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // Without a recorded origin call (e.g. after a process death during
    // which the handler didn't run), NOW counts as the origin. That's the
    // conservative side: the budget then restarts, but it does start - a
    // silent failure of the feature would be the worse choice.
    final origin = appState.snoozeOriginFor(alarmId) ?? DateTime.now();

    if (!canSnooze(
      now: DateTime.now(),
      originalRing: origin,
      snoozeTime: appState.snoozeTime,
      wakeUpBudget: durationFromTimeOfDay(appState.durationToWakeUp),
      snoozeEnabled: appState.snoozeEnabled,
    )) {
      return const SizedBox.shrink();
    }

    final minutes = appState.snoozeTime.inMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          side: BorderSide(color: appState.accentColor, width: 2),
        ),
        onPressed: () async {
          onBeforeSnooze?.call();
          final moved = await snoozeRingingAlarm(
            appState,
            alarmId: alarmId,
            ringTime: origin,
            setAlarm: appState.setSnoozeAlarm,
            stopAlarm: appState.stopPlatformAlarm,
          );
          if (!moved) {
            // FR-20: NOTHING was switched off - the alarm keeps ringing.
            onSnoozeAttemptFailed?.call();
            if (context.mounted) {
              displayToast(context, 'Snooze is used up - time to get up.');
            }
            return;
          }
          onSnoozed?.call();
        },
        child: Text(
          'Snooze $minutes min',
          style: TextStyle(color: appState.accentColor, fontSize: 24),
        ),
      ),
    );
  }
}
