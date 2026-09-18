import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';

// docs/TODO.md T-55: "wrong scheduled alarm infos if opening scheduled alarm
// page before preloading finished" and "duplicate calendar entries for
// preloaded weeks (on first load only?)".
//
// The root cause: `preloadCalendarData` (lib/utils/utils.dart) records each
// preloaded week in `AppState.fetchedCalendarWeeks` keyed by the *start of
// that week*, but `isCalendarWeekFetched` (called by
// `screen_schedule.dart`'s `updateCalendarData` with `appState.visibleDate`,
// an arbitrary day within the week - "today", not necessarily its Monday) had
// compared that raw day against those start-of-week entries. On any day that
// isn't itself the configured start-of-week day, the comparison never
// matched, so a week that had already been preloaded was reported as not
// fetched - triggering a redundant fetch that appended a second copy of the
// same calendar entries to `appState.meetings`.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'T-55: a day is reported as fetched once its week has been, even if the day itself is not the start of the week',
      () async {
    final appState = AppState();
    await appState.initialized;
    appState.startOfWeekDay = 1; // Monday

    // A Wednesday - deliberately not the start of its own week.
    final midWeekDay = DateTime(2026, 9, 23);
    expect(midWeekDay.weekday, DateTime.wednesday);

    final startOfThatWeek = DateTime(2026, 9, 21); // the preceding Monday
    appState.fetchedCalendarWeeks.add(startOfThatWeek);

    expect(await appState.isCalendarWeekFetched(midWeekDay), isTrue);
  });

  test('T-55: a day whose week was never fetched is still reported as such',
      () async {
    final appState = AppState();
    await appState.initialized;
    appState.startOfWeekDay = 1; // Monday

    final midWeekDay = DateTime(2026, 9, 23);
    final startOfADifferentWeek = DateTime(2026, 9, 14);
    appState.fetchedCalendarWeeks.add(startOfADifferentWeek);

    expect(await appState.isCalendarWeekFetched(midWeekDay), isFalse);
  });
}
