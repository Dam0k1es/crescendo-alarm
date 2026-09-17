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
  const SnoozeButton({super.key, required this.alarmId, this.onSnoozed});

  final int alarmId;

  /// Runs after a successful postponement - the screens close themselves in
  /// response to it.
  final VoidCallback? onSnoozed;

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
          final moved = await snoozeRingingAlarm(
            appState,
            alarmId: alarmId,
            ringTime: origin,
            setAlarm: appState.setSnoozeAlarm,
            stopAlarm: appState.stopPlatformAlarm,
          );
          if (!context.mounted) return;
          if (!moved) {
            // FR-20: NOTHING was switched off - the alarm keeps ringing.
            displayToast(context, 'Snooze is used up - time to get up.');
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
