import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-145 (the part kept open after the "fetch on open" concern
// was superseded by T-60): calendar_view's MonthView shows a fixed 6-week
// (42-day) grid, starting from the Monday of the week containing the 1st of
// the month (calendar_view's own `datesOfMonths`) - but `_onPageChange` is
// shared with the week/day views and always calls `updateCalendarData` with
// a fixed 7-day window, regardless of which view triggered it. So paging
// into month view only ever fetches (and marks as fetched) the single week
// containing day 1 - the other ~5 weeks of the visible grid are silently
// left unfetched, and their `Meeting`s never appear in month view unless
// some other path (e.g. the on-open/on-resume resync) happened to also cover
// them.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'a fetch window wider than 7 days marks every week it covers as fetched, not just the first',
      () async {
    final appState = AppState();
    await appState.initialized;

    // A Tuesday - deliberately not a week start, matching what MonthView's
    // onPageChange actually delivers (the 1st of the month).
    appState.visibleDate = DateTime(2026, 9, 1);
    expect(appState.visibleDate.weekday, DateTime.tuesday);

    // The exact window a month-view fetch needs: 6 weeks (42 days) from the
    // Monday of the week containing the 1st.
    await updateCalendarData(appState, const Duration(days: 42));

    // Monday 2026-08-31 is the start of the week containing 2026-09-01.
    final expectedWeekStarts = List.generate(
      6,
      (i) => DateTime(2026, 8, 31).add(Duration(days: i * 7)),
    );

    for (final weekStart in expectedWeekStarts) {
      expect(
        appState.fetchedCalendarWeeks.any((fetched) =>
            fetched.year == weekStart.year &&
            fetched.month == weekStart.month &&
            fetched.day == weekStart.day),
        isTrue,
        reason:
            '$weekStart (one of the 6 weeks a month-view grid covers) should '
            'be marked fetched, not just the first week',
      );
    }
  });
}
