import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/snooze.dart';
import 'package:wakeywakey/utils/utils.dart';

/// FR-20: die Snooze-Schaltfläche des Klingelschirms.
///
/// Bewusst **ein** Widget für beide Schirme (Standard-Overlay und QR-Scanner)
/// statt zweier Kopien: die beiden unterscheiden sich nur darin, wie
/// *abgeschaltet* wird, nicht darin, wie verschoben wird. Zwei Kopien wären
/// zwei Orte, an denen die Budgetprüfung auseinanderlaufen kann - genau die
/// Fehlerklasse, die dieses Projekt bei den fünf Checkpoint-Einstiegspunkten
/// schon einmal getroffen hat (T-87).
///
/// Sie erscheint **nur**, wenn noch Budget da ist. Ist es aufgebraucht, gibt es
/// keinen Knopf - der Wecker klingelt weiter, und es bleibt nur das reguläre
/// Abschalten (auf dem QR-Schirm also mit Scan).
class SnoozeButton extends StatelessWidget {
  const SnoozeButton({super.key, required this.alarmId, this.onSnoozed});

  final int alarmId;

  /// Läuft nach einer erfolgreichen Verschiebung - die Schirme schliessen sich
  /// darüber selbst.
  final VoidCallback? onSnoozed;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // Ohne festgehaltenen Ursprungsruf (etwa nach einem Prozesstod, bei dem
    // der Handler nicht mehr lief) gilt JETZT als Ursprung. Das ist die
    // konservative Seite: das Budget beginnt dann neu, aber es beginnt - ein
    // stiller Ausfall der Funktion wäre die schlechtere Wahl.
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
            // FR-20: es wurde NICHTS abgeschaltet - der Wecker klingelt weiter.
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
