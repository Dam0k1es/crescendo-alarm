import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';

// docs/TODO.md T-137: "Scheduled" is the first tab, "Manual" the second.
//
// What is checked is not the label but the COUPLING: tab index, displayed
// list, and the index the screen's button is pinned to must all match up.
// Swapping only the `tabs:` list and forgetting `TabBarView.children` (or
// vice versa) produces a screen that shows one list while the button
// belongs to the other - and without a test this goes unnoticed, because
// both tabs still look plausible.

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
  testWidgets('Scheduled is tab 1, Manual tab 2', (tester) async {
    final appState = await _appStateWithManualAlarm();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    // The indices themselves.
    expect(ScreenAlarms.scheduledTabIndex, 0);
    expect(ScreenAlarms.manualTabIndex, 1);

    // And the coupling: on the FIRST tab the manual alarm must not be
    // visible - the planned ones are there.
    expect(find.text('03:00'), findsNothing,
        reason: 'tab 1 shows the planned alarms, not the manual ones');

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('03:00'), findsOneWidget,
        reason: 'tab 2 shows the manual alarms');
  });
}
