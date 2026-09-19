import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/sleep_habits/screen_sleephabits.dart';

// docs/TODO.md T-52.1/T-52.3: the two new Sleep Habits controls - the
// gap-day scheduling toggle and the per-weekday "duration to get ready"
// overrides.
Future<AppState> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSleephabits()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  testWidgets(
      'T-52.1: the gap-day toggle reflects and updates AppState.scheduleOnGapDays',
      (tester) async {
    final appState = await _pumpScreen(tester);

    final toggle = find.widgetWithText(
        SwitchListTile, 'Schedule an alarm on days without an appointment');
    expect(toggle, findsOneWidget);
    expect(
        tester.widget<SwitchListTile>(toggle).value, appState.scheduleOnGapDays);
    expect(appState.scheduleOnGapDays, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(appState.scheduleOnGapDays, isFalse);
  });

  testWidgets(
      'T-52.3: expanding per-weekday overrides shows all seven days, each defaulting to off',
      (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Monday'), findsNothing);

    await tester.ensureVisible(find.text('Customize per weekday'));
    await tester.tap(find.text('Customize per weekday'));
    await tester.pumpAndSettle();

    for (final day in [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ]) {
      expect(find.text(day), findsOneWidget);
    }
    // No override set yet, so no per-day time box is shown.
    expect(find.textContaining(' h'), findsWidgets); // the global picker's own
    expect(find.byType(Switch), findsWidgets);
  });

  testWidgets(
      'T-52.3: turning on Monday\'s override starts it at the global value',
      (tester) async {
    final appState = await _pumpScreen(tester);
    appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 45);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Customize per weekday'));
    await tester.tap(find.text('Customize per weekday'));
    await tester.pumpAndSettle();

    expect(appState.durationToGetReadyByWeekday, isEmpty);

    // Scoped to Monday's own row - the page has other Switches above it
    // (SwitchListTile renders one internally too), so an unscoped
    // find.byType(Switch).first would not necessarily be Monday's.
    final mondayRow =
        find.ancestor(of: find.text('Monday'), matching: find.byType(Row)).first;
    final mondaySwitch = find.descendant(
        of: mondayRow, matching: find.byType(Switch));
    await tester.ensureVisible(mondaySwitch);
    await tester.tap(mondaySwitch);
    await tester.pumpAndSettle();

    expect(appState.durationToGetReadyByWeekday.length, 1);
    expect(
        appState.durationToGetReadyForWeekday(
            appState.durationToGetReadyByWeekday.keys.first),
        const TimeOfDay(hour: 0, minute: 45));
  });
}
