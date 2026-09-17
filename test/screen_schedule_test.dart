import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-05: a smoke test for the migrated Schedule screen.
//
// test/schedule_events_test.dart covers the mapping, which is where the
// migration could go wrong *quietly*. This covers the other half: that the
// screen still builds at all, and that the views SfCalendar used to offer
// (day, week, work week, month) are all still reachable. A calendar library
// swap that leaves the app showing a red error box would otherwise only be
// noticed on a device.

Future<AppState> _pumpSchedule(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ScreenSchedule()),
    ),
  );
  await tester.pump();
  return appState;
}

void main() {
  testWidgets('the schedule screen renders a week view', (tester) async {
    await _pumpSchedule(tester);

    expect(find.byType(WeekView<Meeting>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every view SfCalendar offered is still reachable',
      (tester) async {
    await _pumpSchedule(tester);

    // Day
    await tester.tap(find.byTooltip('Calendar View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day').last);
    await tester.pumpAndSettle();
    expect(find.byType(DayView<Meeting>), findsOneWidget);

    // Work week - still a WeekView, but a five-day one. The distinction is
    // checked in the widget's own configuration rather than by counting
    // columns, which would be testing calendar_view rather than this app.
    await tester.tap(find.byTooltip('Calendar View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work week').last);
    await tester.pumpAndSettle();
    final workWeek = tester.widget<WeekView<Meeting>>(find.byType(WeekView<Meeting>));
    expect(workWeek.weekDays, hasLength(5));
    expect(workWeek.weekDays, isNot(contains(WeekDays.saturday)));

    // Month
    await tester.tap(find.byTooltip('Calendar View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();
    expect(find.byType(MonthView<Meeting>), findsOneWidget);

    // ...and back to the full week.
    await tester.tap(find.byTooltip('Calendar View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();
    final week = tester.widget<WeekView<Meeting>>(find.byType(WeekView<Meeting>));
    expect(week.weekDays, hasLength(7));
  });

  testWidgets('the week starts on Monday', (tester) async {
    // `firstDayOfWeek: 1` in the SfCalendar configuration this replaced. Easy
    // to lose in a migration and immediately wrong for the user.
    await _pumpSchedule(tester);

    final week = tester.widget<WeekView<Meeting>>(find.byType(WeekView<Meeting>));
    expect(week.startDay, WeekDays.monday);
  });
}
