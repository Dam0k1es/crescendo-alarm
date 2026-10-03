import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-221 (maintainer request): "Ich will, dass der alarm als
// inaktiv gelistet wird." - a switched-off scheduled alarm stays on the
// Scheduled tab with its switch off.

Future<AppState> _pump(WidgetTester tester, List<ScheduledAlarm> alarms) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  FakeAlarmPlatform().attach(appState);
  appState.scheduledAlarms = alarms;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ScreenAlarms()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  testWidgets('a disabled scheduled alarm is listed with its switch off',
      (tester) async {
    await _pump(tester, [
      ScheduledAlarm(time: DateTime(2026, 9, 21, 6, 45), enabled: false, id: 1),
      ScheduledAlarm(time: DateTime(2026, 9, 22, 7, 15), enabled: true, id: 2),
    ]);

    expect(find.byType(Card), findsNWidgets(2),
        reason: 'the inactive entry is listed, not hidden');
    final switches =
        tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.map((s) => s.value), [false, true]);
  });

  testWidgets(
      'switching an entry off writes the day veto, shows the switch off at '
      'once, and leaves the entry itself to FR-18', (tester) async {
    final alarm =
        ScheduledAlarm(time: DateTime(2026, 9, 22, 7, 15), enabled: true, id: 2);
    final appState = await _pump(tester, [alarm]);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(appState.isDayDisabled(isoDate(alarm.time)), isTrue,
        reason: 'FR-21: the toggle is a statement about the day');
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    // The entry is not flipped in place: an entry that says "disabled" while
    // its platform alarm is still armed would be kept by the reconciliation
    // as a matching inactive entry - and ring. Only planAlarmSync replaces
    // it (stopping the armed one), whatever the platform state.
    expect(alarm.enabled, isTrue);
  });
}
