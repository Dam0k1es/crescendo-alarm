import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart' as plus;
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/utils.dart';

// docs/TODO.md T-244 (review N3): the Schedule's fetch window was built with
// `startOfWeek.add(Duration(days: 7))`. On a local DateTime that is 168
// hours, so across a daylight-saving change the end landed an hour off the
// next Monday's midnight (a week from Mon 19 Oct to Mon 26 Oct 2026 crosses
// Europe/Berlin's change on Sun 25 Oct). The window is calendar days.

void main() {
  tearDown(() {
    calendars = [];
    resetCalendarSourcesForTest();
  });

  test('addCalendarDays moves by calendar days, not by 24-hour multiples', () {
    expect(addCalendarDays(DateTime(2026, 10, 19), 7), DateTime(2026, 10, 26));
    expect(addCalendarDays(DateTime(2026, 3, 23), 7), DateTime(2026, 3, 30));
    expect(addCalendarDays(DateTime(2026, 10, 26), -7), DateTime(2026, 10, 19));
  });

  test('a week fetch across a DST change ends at the next Monday midnight',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;
    calendars = [
      plus.Calendar(id: 'a', name: 'a', readOnly: true),
    ];
    final windows = <List<DateTime>>[];
    listEventsFromDevice = (start, end, id) async {
      windows.add([start, end]);
      return [];
    };
    appState.visibleDate = DateTime(2026, 10, 21);

    await updateCalendarData(appState, const Duration(days: 7));

    expect(windows.single, [DateTime(2026, 10, 19), DateTime(2026, 10, 26)]);
  });
}
