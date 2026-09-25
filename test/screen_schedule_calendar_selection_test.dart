import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-53: a checkable calendar list, reachable from a corner
// button in the Schedule screen's app bar, that filters which calendars
// feed both the display and scheduling.
Future<AppState> _pumpSchedule(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSchedule()),
    ),
  );
  await tester.pump();
  return appState;
}

void main() {
  setUp(() {
    calendars = [
      Calendar(id: 'work-id', name: 'Work', color: 0xFF0000FF),
      Calendar(id: 'personal-id', name: 'Personal', color: 0xFFFF0000),
    ];
  });

  tearDown(() {
    calendars = [];
  });

  testWidgets('the corner button opens a checkable list of every calendar',
      (tester) async {
    await _pumpSchedule(tester);

    await tester.tap(find.byTooltip('Calendars'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    // Every calendar is selected by default.
    final workTile =
        tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Work'));
    expect(workTile.value, isTrue);
  });

  testWidgets(
      'unchecking a calendar updates AppState and stays reflected on reopen',
      (tester) async {
    final appState = await _pumpSchedule(tester);

    await tester.tap(find.byTooltip('Calendars'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Personal'));
    await tester.pumpAndSettle();

    expect(appState.isCalendarSelected('personal-id'), isFalse);
    expect(appState.isCalendarSelected('work-id'), isTrue);

    final personalTile = tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Personal'));
    expect(personalTile.value, isFalse,
        reason: 'the sheet must reflect the change without needing to be '
            'closed and reopened');

    // Close and reopen: still reflects the persisted state.
    Navigator.of(tester.element(find.byTooltip('Calendars'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Calendars'));
    await tester.pumpAndSettle();

    final reopened = tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Personal'));
    expect(reopened.value, isFalse);
  });

  testWidgets('no calendars found shows a fallback message', (tester) async {
    calendars = [];
    await _pumpSchedule(tester);

    await tester.tap(find.byTooltip('Calendars'));
    await tester.pumpAndSettle();

    expect(find.text('No calendars found on this device.'), findsOneWidget);
  });

  testWidgets(
      'a device with many calendars does not overflow the sheet',
      (tester) async {
    // A real device with several accounts (each with its own holiday/
    // birthday calendars) can easily have a dozen+ calendars - the sheet's
    // plain, non-scrolling Column used to overflow rather than scroll.
    calendars = List.generate(
      20,
      (i) => Calendar(id: 'cal-$i', name: 'Calendar number $i', color: 0xFF0000FF),
    );
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpSchedule(tester);

    await tester.tap(find.byTooltip('Calendars'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
