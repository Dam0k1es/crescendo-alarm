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

Future<AppState> _pumpSchedule(WidgetTester tester,
    {bool alwaysUse24HourFormat = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      // docs/TODO.md T-52.2: the hour axis follows this MediaQuery flag now,
      // not a hardcoded format - defaulted to true here so every other test
      // in this file keeps seeing the 24h axis it was written against.
      child: MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: alwaysUse24HourFormat),
        child: const MaterialApp(home: ScreenSchedule()),
      ),
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
    final workWeek =
        tester.widget<WeekView<Meeting>>(find.byType(WeekView<Meeting>));
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
    final week =
        tester.widget<WeekView<Meeting>>(find.byType(WeekView<Meeting>));
    expect(week.weekDays, hasLength(7));
  });

  testWidgets('the calendar takes its colours from the app theme',
      (tester) async {
    // calendar_view paints in its own palette by default - a bright red header
    // and pink grid lines, which is what the first Linux run of the migrated
    // screen actually showed. In dark mode the weekday strip and the hour
    // labels were additionally near-invisible, and those two have no
    // widget-level parameter at all.
    //
    // The assertion deliberately reads the theme the way the WIDGET reads it,
    // `Theme.of(context).extension<...>()`. An earlier version asserted that
    // the package's `CalendarThemeProvider` held the right data - it did, and
    // the screen still rendered red, because nothing consumes that provider.
    // A test that checks the wrong channel is worse than no test.
    await _pumpSchedule(tester);

    final context = tester.element(find.byType(WeekView<Meeting>));
    final scheme = Theme.of(context).colorScheme;
    final week = Theme.of(context).extension<WeekViewThemeData>();
    final month = Theme.of(context).extension<MonthViewThemeData>();

    expect(week, isNotNull,
        reason: 'without the extension the widget falls back to the '
            "library's light palette");
    expect(week!.headerBackgroundColor, scheme.surface);
    expect(week.pageBackgroundColor, scheme.surface);
    expect(week.headerTextColor, scheme.onSurface);
    // The two dark-mode offenders.
    expect(week.weekDayTextColor, scheme.onSurface);
    expect(week.timelineTextColor, scheme.onSurfaceVariant);
    // And the month view, a separate palette in this library.
    expect(month?.cellTextColor, scheme.onSurface);
    expect(month?.headerBackgroundColor, scheme.surface);
  });

  testWidgets('the live-time indicator uses the accent colour', (tester) async {
    final appState = await _pumpSchedule(tester);

    final context = tester.element(find.byType(WeekView<Meeting>));
    expect(Theme.of(context).extension<WeekViewThemeData>()?.liveIndicatorColor,
        appState.accentColor);
    expect(Theme.of(context).extension<DayViewThemeData>()?.liveIndicatorColor,
        appState.accentColor);
  });

  testWidgets(
      'the hour axis is 24-hour when the device is set to 24-hour format',
      (tester) async {
    // SfCalendar was configured with `timeFormat: 'HH:mm'`; calendar_view's
    // default mark reads "1 PM". An independent review found the setting had
    // been dropped in the migration - immediately visible, and wrong for most
    // of this app's users.
    await _pumpSchedule(tester, alwaysUse24HourFormat: true);
    await tester.pumpAndSettle();

    expect(find.text('13:00'), findsWidgets);
    expect(find.textContaining('PM'), findsNothing);
  });

  testWidgets(
      'docs/TODO.md T-52.2: the hour axis is 12-hour AM/PM when the device is not',
      (tester) async {
    // The axis used to hardcode 'HH:mm' regardless of the device's own
    // setting - wrong for exactly the users this covers.
    await _pumpSchedule(tester, alwaysUse24HourFormat: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('PM'), findsWidgets);
    expect(find.text('13:00'), findsNothing);
  });

  testWidgets('paging does not tear the calendar down', (tester) async {
    // The view key must not contain the displayed date: paging writes
    // `visibleDate`, which notifies listeners, which rebuilds this screen - so
    // a date in the key destroyed and recreated the WeekView on every swipe,
    // resetting the time grid's scroll to midnight.
    await _pumpSchedule(tester);
    await tester.pumpAndSettle();
    final before = tester.state(find.byType(WeekView<Meeting>));

    // A real swipe, not a simulated one: it is the library's own page change
    // that writes `visibleDate`, and that write is what rebuilds this screen.
    await tester.drag(find.byType(PageView).first, const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(WeekView<Meeting>)), same(before),
        reason: 'same State object - the calendar was not rebuilt from '
            'scratch, so the time grid keeps its scroll position');
  });

  testWidgets('the week starts on Monday', (tester) async {
    // `firstDayOfWeek: 1` in the SfCalendar configuration this replaced. Easy
    // to lose in a migration and immediately wrong for the user.
    await _pumpSchedule(tester);

    final week =
        tester.widget<WeekView<Meeting>>(find.byType(WeekView<Meeting>));
    expect(week.startDay, WeekDays.monday);
  });
}
