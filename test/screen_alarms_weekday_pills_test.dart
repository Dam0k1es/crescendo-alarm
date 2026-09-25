import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';

// User request: always see which day(s) a manual alarm rings on, right on
// the alarm list, as a small pill per weekday - not only inside the edit
// dialog.
Future<AppState> _pumpAlarmsScreen(WidgetTester tester,
    {required Map<DayOfWeek, bool> repeatOnDays}) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.manualAlarms.add(
    ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      repeatOnDays: repeatOnDays,
    ),
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ScreenAlarms()),
    ),
  );
  await tester.pumpAndSettle();
  // The Manual tab is second (docs/TODO.md T-137).
  await tester.tap(find.text('Manual'));
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  testWidgets('a manual alarm shows all seven weekday pills',
      (tester) async {
    await _pumpAlarmsScreen(tester,
        repeatOnDays: {for (final day in DayOfWeek.values) day: true});

    for (final label in ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']) {
      expect(find.text(label), findsOneWidget,
          reason: 'every weekday must have its own pill, always visible on '
              'the list, not only inside the edit dialog');
    }
  });

  testWidgets(
      'a weekday-only alarm visually distinguishes its active days from inactive ones',
      (tester) async {
    final appState = await _pumpAlarmsScreen(tester, repeatOnDays: {
      DayOfWeek.monday: true,
      DayOfWeek.tuesday: true,
      DayOfWeek.wednesday: true,
      DayOfWeek.thursday: true,
      DayOfWeek.friday: true,
      DayOfWeek.saturday: false,
      DayOfWeek.sunday: false,
    });

    final accent = appState.accentColor;
    final monday = tester.widget<CircleAvatar>(find.ancestor(
        of: find.text('Mo'), matching: find.byType(CircleAvatar)));
    final saturday = tester.widget<CircleAvatar>(find.ancestor(
        of: find.text('Sa'), matching: find.byType(CircleAvatar)));

    expect(monday.backgroundColor, accent);
    expect(saturday.backgroundColor, isNot(accent));
  });

  testWidgets('a scheduled alarm (no repeatOnDays of its own) shows no pills',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.scheduledAlarms.add(
      ScheduledAlarm(time: DateTime(2026, 9, 21, 7, 0)),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mo'), findsNothing,
        reason: 'a ScheduledAlarm has no weekly repeat pattern of its own - '
            'it is a single calendar-derived day, so it gets no pill row');
  });
}
