import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';

// docs/TODO.md T-137: "Scheduled" ist der erste Reiter, "Manual" der zweite.
//
// Gepruefft wird nicht die Beschriftung, sondern die KOPPLUNG: Reiterindex,
// angezeigte Liste und der Index, an dem der Schirm seinen Knopf festmacht,
// muessen zusammenpassen. Wer nur die `tabs:`-Liste tauscht und die
// `TabBarView.children` vergisst (oder umgekehrt), bekommt einen Schirm, der
// die eine Liste zeigt, waehrend der Knopf zur anderen gehoert - und das faellt
// ohne Test nicht auf, weil beide Reiter weiterhin plausibel aussehen.

Future<AppState> _appStateWithManualAlarm() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.manualAlarms.add(
    ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0)),
  );
  return appState;
}

void main() {
  testWidgets('Scheduled ist Reiter 1, Manual Reiter 2', (tester) async {
    final appState = await _appStateWithManualAlarm();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    // Die Indizes selbst.
    expect(ScreenAlarms.scheduledTabIndex, 0);
    expect(ScreenAlarms.manualTabIndex, 1);

    // Und die Kopplung: auf dem ERSTEN Reiter darf der manuelle Alarm nicht
    // zu sehen sein - dort stehen die geplanten.
    expect(find.text('03:00'), findsNothing,
        reason: 'Reiter 1 zeigt die geplanten Alarme, nicht die manuellen');

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('03:00'), findsOneWidget,
        reason: 'Reiter 2 zeigt die manuellen Alarme');
  });
}
