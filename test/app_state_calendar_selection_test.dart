import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';

// docs/TODO.md T-53: which device_calendar calendars feed the Schedule
// display and scheduling. Stores what's explicitly DESELECTED, not what's
// selected, so a calendar the device adds later (never seen before) is
// included by default rather than silently dropped.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('every calendar is selected by default, matching every existing install',
      () async {
    final appState = AppState();
    await appState.initialized;

    expect(appState.isCalendarSelected('work-calendar-id'), isTrue);
    expect(appState.isCalendarSelected('any-other-id'), isTrue);
    expect(appState.deselectedCalendarIds, isEmpty);
  });

  test('deselecting a calendar excludes only that one, and round-trips',
      () async {
    final first = AppState();
    await first.initialized;

    first.setCalendarSelected('personal', false);

    expect(first.isCalendarSelected('personal'), isFalse);
    expect(first.isCalendarSelected('work'), isTrue);

    final second = AppState();
    await second.initialized;
    expect(second.isCalendarSelected('personal'), isFalse);
    expect(second.isCalendarSelected('work'), isTrue);
  });

  test('re-selecting a deselected calendar clears it, not just flips a flag',
      () async {
    final appState = AppState();
    await appState.initialized;

    appState.setCalendarSelected('personal', false);
    appState.setCalendarSelected('personal', true);

    expect(appState.isCalendarSelected('personal'), isTrue);
    // A calendar that was never deselected in the first place must not
    // leave a stray entry behind either.
    expect(appState.deselectedCalendarIds, isEmpty);
  });

  test('notifies listeners on change', () async {
    final appState = AppState();
    await appState.initialized;
    var notified = false;
    appState.addListener(() => notified = true);

    appState.setCalendarSelected('personal', false);

    expect(notified, isTrue);
  });
}
