import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// New feature (user request): a calendar event can be marked "ignored" -
// grayed out with an X on its tile, toggled by tapping it, persisted without
// ever writing back to the calendar. The scheduling-side effect (an ignored
// event produces no hardFloor) is covered by test/replan_ignored_events_test
// .dart and the persistence itself by test/ignored_events_test.dart; this
// file is the UI half - the tap interaction and the visual mark.

Future<AppState> _pumpScheduleWithMeeting(
    WidgetTester tester, Meeting meeting) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  appState.meetings = [meeting];

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ScreenSchedule()),
    ),
  );
  await tester.pump();
  // updateCalendarData's own calendar fetch throws in a unit test (no
  // device_calendar channel) and is caught internally - a couple of pumps
  // let that settle before the sync-to-_events step (which runs regardless
  // of the fetch outcome, using appState.meetings as the source of truth)
  // is checked.
  updateCalendarData(appState, const Duration(days: 7));
  await tester.pump();
  await tester.pump();
  return appState;
}

Meeting _todayMeeting({String id = 'evt-1', String title = 'Team Meeting'}) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day, 10, 0);
  return Meeting(
    from: from,
    to: from.add(const Duration(hours: 1)),
    isAllDay: false,
    startTimeZone: 'Etc/UTC',
    endTimeZone: 'Etc/UTC',
    eventName: title,
    ids: [id],
  );
}

void main() {
  testWidgets('a non-ignored event shows no X mark', (tester) async {
    await _pumpScheduleWithMeeting(tester, _todayMeeting());

    expect(find.byType(IgnoredEventMark), findsNothing);
  });

  testWidgets(
      'tapping an event opens a sheet that toggles its ignored state',
      (tester) async {
    final meeting = _todayMeeting();
    final appState = await _pumpScheduleWithMeeting(tester, meeting);

    await tester.ensureVisible(find.text('Team Meeting').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team Meeting').first);
    await tester.pumpAndSettle();

    expect(find.text('Ignore for scheduling'), findsOneWidget);
    expect(appState.isEventIgnored(meeting), isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(appState.isEventIgnored(meeting), isTrue,
        reason: 'the toggle must actually reach AppState, which is the '
            'durable, calendar-independent store for this');
  });

  testWidgets('an ignored event is shown with the X mark on its tile',
      (tester) async {
    final meeting = _todayMeeting();
    final appState = await _pumpScheduleWithMeeting(tester, meeting);
    appState.setEventIgnored(meeting, true);
    await tester.pump();

    expect(find.byType(IgnoredEventMark), findsOneWidget);
  });

  testWidgets('un-ignoring removes the X mark again', (tester) async {
    final meeting = _todayMeeting();
    final appState = await _pumpScheduleWithMeeting(tester, meeting);
    appState.setEventIgnored(meeting, true);
    await tester.pump();

    await tester.ensureVisible(find.text('Team Meeting').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team Meeting').first);
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    final switchWidget = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile));
    expect(switchWidget.value, isTrue,
        reason: 'the sheet must reflect the already-ignored state on open');

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(appState.isEventIgnored(meeting), isFalse);
    expect(find.byType(IgnoredEventMark), findsNothing);
  });
}
