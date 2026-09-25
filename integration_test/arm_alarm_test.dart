// Ein Vorlauf fuer .github/scripts/check_alarm_survival.sh (docs/TODO.md T-93,
// docs/REQUIREMENTS.md R3): stellt genau einen Alarm weit in der Zukunft
// scharf und laesst ihn STEHEN.
//
// Warum eine eigene Datei: app_test.dart raeumt in `setUp` und `tearDown`
// konsequent mit `Alarm.stopAll()` auf, damit die Szenarien voneinander
// unabhaengig sind. Genau das macht es unmoeglich, aus dieser Suite heraus
// einen Alarm fuer eine Reboot-Pruefung zu hinterlassen - und ohne einen
// registrierten Alarm kann `dumpsys alarm` nach dem Reboot nichts aussagen.
//
// Zwei Stunden Vorlauf: der Alarm darf waehrend des Testlaufs nicht klingeln
// (das wuerde das Overlay hochziehen und die Beweissammlung stoeren), muss aber
// weit genug in der Zukunft liegen, dass ihn die Stale-Logik des Plugins beim
// Boot nicht als verpasst verwirft.

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('arms a single alarm two hours out and leaves it registered',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await Alarm.stopAll();

    final appState = AppState();
    await appState.initialized;

    final target = DateTime.now().add(const Duration(hours: 2));
    final result = await appState.addAlarm(ManualAlarm(
      time: TimeOfDay(hour: target.hour, minute: target.minute),
    ));
    expect(result['success'], isTrue,
        reason: 'ohne registrierten Alarm ist die Reboot-Pruefung wertlos: '
            '${result['errMsg']}');

    final onPlatform = await Alarm.getAlarms();
    expect(onPlatform, isNotEmpty,
        reason: 'der Alarm muss beim Plugin angekommen sein, sonst kann '
            'dumpsys alarm ihn nach dem Reboot nicht wiederfinden');

    // Bewusst KEIN Alarm.stopAll() hier - der Alarm soll den Reboot erleben.
  });
}
