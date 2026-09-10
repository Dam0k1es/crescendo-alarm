import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';

// docs/TODO.md T-96: der Dialog zum Anlegen eines manuellen Alarms
// vorbelegt gentlewake, volume und tone aus dem AppState
// (screen_alarms.dart:265-267) - die neue Rampendauer aber zunaechst nicht.
// Ein manueller Alarm haette damit stur die Default-Minute benutzt und die
// Einstellung des Nutzers ignoriert. Das ist genau die Fehlerklasse aus T-84:
// eine Einstellung mit UI, die den Alarm nie erreicht.

void main() {
  testWidgets('ein neuer manueller Alarm erbt Rampendauer, Lautstaerke und Ton',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;
    appState.gentleWakeUpEnabled = true;
    appState.gentleWakeUpDuration = const Duration(minutes: 9);
    appState.selectedVolume = 0.42;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final created = appState.manualAlarms.single;
    expect(created.gentlewake, isTrue);
    expect(created.gentleWakeDuration, const Duration(minutes: 9),
        reason: 'die konfigurierte Rampendauer muss am Alarm ankommen - '
            'sonst ist es T-84 noch einmal');
    // Die beiden, die schon vorher uebernommen wurden - als Absicherung, dass
    // die Vorbelegung insgesamt intakt bleibt.
    expect(created.volume, 0.42);
    expect(created.tone, appState.selectedTone);
  });
}
