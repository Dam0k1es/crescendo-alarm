import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/utils.dart';

// docs/TODO.md T-60: `preloadCalendarData` alone only ever ran once per
// process lifetime - nothing cleared `AppState.meetings` or
// `fetchedCalendarWeeks` afterwards, so a calendar edit made after that
// first fetch stayed invisible until the app was killed and relaunched.
// `resyncCalendarData` is the function called on every app open instead
// (lib/main.dart) - it must replace the stale state, not add to it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('T-60: clears stale meetings and fetched weeks before re-preloading',
      () async {
    final appState = AppState();
    await appState.initialized;

    // Simulate state left over from an earlier preload/fetch.
    appState.meetings = [
      Meeting(
        from: DateTime(2020, 1, 1),
        to: DateTime(2020, 1, 1, 1),
        startTimeZone: '',
        endTimeZone: '',
      ),
    ];
    appState.fetchedCalendarWeeks = [DateTime(2020, 1, 1)];

    await resyncCalendarData(appState, pastWeeks: 1, futureWeeks: 1);

    // The test environment has no calendars (T-05/T-33's Linux gap), so a
    // fresh fetch returns zero meetings - the stale one must be gone, not
    // still present alongside whatever the fresh fetch found.
    expect(appState.meetings, isEmpty);
    // The stale 2020 week must not survive the resync either.
    expect(appState.fetchedCalendarWeeks, isNot(contains(DateTime(2020, 1, 1))));
  });

  test('T-60: repeated resyncs do not accumulate duplicate fetched weeks',
      () async {
    final appState = AppState();
    await appState.initialized;

    await resyncCalendarData(appState, pastWeeks: 1, futureWeeks: 1);
    final firstRunCount = appState.fetchedCalendarWeeks.length;

    await resyncCalendarData(appState, pastWeeks: 1, futureWeeks: 1);

    // A second resync clears the list first (asserted above), so it should
    // end up with exactly the same number of weeks as the first run, not
    // more - each run's own two calls (the internal "now" fetch and the
    // preload loop) must not double-count the current week either.
    expect(appState.fetchedCalendarWeeks.length, firstRunCount);
  });
}
