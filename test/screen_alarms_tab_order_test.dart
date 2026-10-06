import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-137 put "Scheduled" first; the maintainer reversed the
// visual order on 2026-10-06: "Schiebe manual alarms nach links und
// scheduled alarms nach rechts." - "Manual" is now the LEFT tab, "Scheduled"
// the RIGHT one. The screen still OPENS on "Scheduled": T-137's reason for
// that (it is what a user looks at every day) does not depend on where the
// tab sits.
//
// What is checked is not the label alone but the COUPLING: tab position,
// displayed list, the floating button and swipe-left "delete all" must all
// belong to the same tab. Swapping only the `tabs:` list and forgetting
// `TabBarView.children` (or the index constants) produces a screen that
// shows one list while the actions act on the other - and both tabs still
// look plausible.

Future<AppState> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  FakeAlarmPlatform().attach(appState);
  appState.manualAlarms.add(
    ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0)),
  );
  appState.scheduledAlarms = [
    ScheduledAlarm(time: DateTime(2026, 9, 22, 7, 15), enabled: true, id: 2),
  ];

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
  testWidgets('Manual is the left tab, Scheduled the right one',
      (tester) async {
    await _pump(tester);

    expect(ScreenAlarms.manualTabIndex, 0);
    expect(ScreenAlarms.scheduledTabIndex, 1);

    final manualX = tester.getCenter(find.text('Manual')).dx;
    final scheduledX = tester.getCenter(find.text('Scheduled')).dx;
    expect(manualX, lessThan(scheduledX),
        reason: '"Manual" sits left of "Scheduled" in the tab bar');
  });

  testWidgets('opens on Scheduled: planned list and the sync button',
      (tester) async {
    await _pump(tester);

    expect(find.text('07:15'), findsOneWidget,
        reason: 'the default tab shows the planned alarms');
    expect(find.text('03:00'), findsNothing);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('each tab shows its own list and its own button',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(find.text('03:00'), findsOneWidget,
        reason: 'the Manual tab shows the manual alarms');
    expect(find.text('07:15'), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget,
        reason: 'the Add button belongs to the Manual tab');
    expect(find.byIcon(Icons.sync), findsNothing);

    await tester.tap(find.text('Scheduled'));
    await tester.pumpAndSettle();
    expect(find.text('07:15'), findsOneWidget);
    expect(find.text('03:00'), findsNothing);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('swipe-left on the Manual tab deletes only manual alarms',
      (tester) async {
    final appState = await _pump(tester);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('03:00'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(appState.manualAlarms, isEmpty);
    expect(appState.scheduledAlarms, hasLength(1),
        reason: "the other tab's list is untouched");
  });

  testWidgets('swipe-left on the Scheduled tab deletes only scheduled alarms',
      (tester) async {
    final appState = await _pump(tester);

    await tester.drag(find.text('07:15'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(appState.scheduledAlarms, isEmpty);
    expect(appState.manualAlarms, hasLength(1),
        reason: "the other tab's list is untouched");
  });
}
