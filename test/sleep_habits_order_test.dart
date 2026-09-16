import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/sleep_habits/screen_sleephabits.dart';

// docs/TODO.md T-95: die Reihenfolge der Einträge auf dem Sleep-Habits-Schirm.
//
// Der Defekt der alten Reihenfolge war nicht Geschmack, sondern eine falsche
// Ursachenzuordnung: "Sleep Goal" stand an erster Stelle, beeinflusst aber die
// Alarmzeit überhaupt nicht - es verschiebt ausschließlich die
// Bettgeh-Erinnerung (nextWakeUpTime - sleepGoal - reminderDuration, siehe
// lib/utils/sleep_reminder.dart). Wer es oben sieht und daran dreht, erwartet
// einen früheren Wecker und bekommt nichts. Gleichzeitig war es von "Enable
// Reminder" - seiner anderen Hälfte derselben Rechnung - durch drei fremde
// Einträge getrennt, und "Preferred wake-up time", der Anker der ganzen
// FR-4-Drift und die einzige Einstellung, die ein Nutzer ohne Kalendertermine
// überhaupt braucht, lag auf Position 4 unter zwei Dauern, die nur bei
// vorhandenem Termin wirken.
//
// Getestet wird über die y-Position der Beschriftungen, nicht über die
// Reihenfolge im Quelltext: geprüft werden soll, was der Nutzer sieht.

Future<AppState> _appStateWithAllTilesVisible() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  // Beide aufklappbaren Bereiche öffnen, damit alle Einträge im Baum liegen.
  appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  appState.reminderEnabled = true;
  appState.gentleWakeUpEnabled = true;
  return appState;
}

Future<void> _pumpScreen(WidgetTester tester, AppState appState) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSleephabits()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Die y-Positionen der genannten Texte, in der Reihenfolge der Liste.
List<double> _verticalPositions(WidgetTester tester, List<String> labels) {
  return labels.map((label) {
    final finder = find.text(label);
    expect(finder, findsOneWidget,
        reason: 'Beschriftung "$label" nicht (oder mehrfach) gefunden');
    return tester.getTopLeft(finder).dy;
  }).toList();
}

void main() {
  testWidgets('die Einträge stehen in ursächlicher Reihenfolge', (tester) async {
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    // Drei Gruppen, jede in sich ursächlich geordnet:
    //
    // 1. Was bestimmt, WANN der Wecker klingelt. Zuerst das Ziel, auf das FR-4
    //    zudriftet; dann die Schranke, wie schnell er sich ihm nähern darf;
    //    dann die zwei Vorlaufzeiten, die nur an Tagen mit Termin überhaupt
    //    greifen - in der Reihenfolge, in der sie real anfallen und in der
    //    hardFloor sie abzieht (erst aufwachen, dann fertig werden).
    // 2. Was die Bettgeh-Erinnerung bestimmt. Das Schlafziel definiert die
    //    Bettzeit, der Vorlauf misst sich von ihr aus - also in dieser Folge.
    // 3. Wie sich der Alarm beim Klingeln verhält.
    final expectedOrder = <String>[
      'Preferred wake-up time',
      'Max. daily shift',
      'Duration to wake up',
      'Duration to get ready',
      'Sleep Goal',
      'Enable Reminder',
      'Gentle WakeUp',
    ];

    final positions = _verticalPositions(tester, expectedOrder);

    for (var i = 1; i < positions.length; i++) {
      expect(
        positions[i],
        greaterThan(positions[i - 1]),
        reason: '"${expectedOrder[i]}" muss unter "${expectedOrder[i - 1]}" '
            'stehen, liegt aber bei y=${positions[i]} gegenüber '
            'y=${positions[i - 1]}',
      );
    }
  });

  testWidgets('jede Gruppe traegt eine Ueberschrift ueber ihrem ersten Eintrag',
      (tester) async {
    // Ohne Überschriften ist die Gruppierung für den Nutzer unsichtbar - dann
    // wäre die neue Reihenfolge nur eine andere, keine erklärte.
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    final pairs = <String, String>{
      'Wake-up time': 'Preferred wake-up time',
      'Bedtime reminder': 'Sleep Goal',
      'When the alarm rings': 'Gentle WakeUp',
    };

    pairs.forEach((header, firstItem) {
      final headerFinder = find.text(header);
      expect(headerFinder, findsOneWidget,
          reason: 'Gruppen-Überschrift "$header" fehlt');
      expect(
        tester.getTopLeft(headerFinder).dy,
        lessThan(tester.getTopLeft(find.text(firstItem)).dy),
        reason: '"$header" muss über "$firstItem" stehen',
      );
    });
  });

  testWidgets('der Hinweis zum Minimum bleibt bei "Max. daily shift"',
      (tester) async {
    // Der Hinweis aus T-88 darf beim Umsortieren nicht von seinem Regler
    // getrennt werden - allein stehend wäre er sinnlos.
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    final hint = find.textContaining('smaller values are raised');
    expect(hint, findsOneWidget);
    expect(
      tester.getTopLeft(hint).dy,
      greaterThan(tester.getTopLeft(find.text('Max. daily shift')).dy),
    );
    expect(
      tester.getTopLeft(hint).dy,
      lessThan(tester.getTopLeft(find.text('Duration to wake up')).dy),
      reason: 'der Hinweis gehört noch in die Kachel von "Max. daily shift"',
    );
  });

  // docs/TODO.md T-96: Gentle Wake hatte keinen Regler - die Rampe war auf
  // 60 Sekunden festverdrahtet.
  testWidgets('Gentle Wake zeigt einen Regler fuer die Rampendauer',
      (tester) async {
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    final label = find.text('Ramp duration');
    expect(label, findsOneWidget, reason: 'Regler fuer die Rampendauer fehlt');
    expect(
      tester.getTopLeft(label).dy,
      greaterThan(tester.getTopLeft(find.text('Gentle WakeUp')).dy),
      reason: 'der Regler gehoert unter seinen Schalter',
    );

    // Wie bei maxDailyDelta (T-88) darf das erzwungene Minimum nicht
    // unsichtbar sein - der hh:mm-Picker laesst 00:00 zu, das Plugin nicht.
    expect(find.textContaining('At least 00:01'), findsOneWidget,
        reason: 'Hinweis auf das Minimum fehlt');
  });

  testWidgets('ist Gentle Wake aus, gibt es auch keinen Regler', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;
    appState.gentleWakeUpEnabled = false;
    await _pumpScreen(tester, appState);

    expect(find.text('Ramp duration'), findsNothing);
  });
}
