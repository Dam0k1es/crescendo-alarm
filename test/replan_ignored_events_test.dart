import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// New feature (user request): an ignored calendar event must not produce a
// hardFloor - the point of the feature is to let the user opt an appointment
// out of driving the wake-up time entirely, without writing anything back to
// the (possibly shared) calendar. replan() is the single place `allEvents`
// is assembled before every downstream scheduling-v2 function sees it
// (`eventsForDay`/`hardFloor` in scheduling_v2.dart), so filtering there once
// keeps every pure function in that file unaware ignoring exists at all - the
// same "keep the domain layer pure" shape as FR-15 (manual alarms) and FR-21
// (disabledDays).

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

Meeting _meetingAt(DateTime from, {String id = 'evt-1'}) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
      ids: [id],
    );

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  test('an ignored event does not produce a hardFloor - the day becomes a '
      'gap day', () async {
    final appState = await _freshAppState();
    final ringDay = _utc(0, 0, day: 10);
    final eventDay = _utc(7, 30, day: 16);
    appState.setEventIgnored(_meetingAt(eventDay, id: 'evt-ignored'), true);

    await replan(
      appState,
      now: () => ringDay,
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async =>
          [_meetingAt(eventDay, id: 'evt-ignored')],
    );

    expect(appState.pendingDayValues['2026-03-16'], isNull,
        reason: 'the only event on this day was ignored - it must plan as '
            'a gap day, exactly as if the event never existed');
  });

  test('an un-ignored event still produces its hardFloor as normal',
      () async {
    // Counter-test against over-filtering: an event that was never ignored
    // must plan exactly as before.
    final appState = await _freshAppState();
    final ringDay = _utc(0, 0, day: 10);
    final eventDay = _utc(7, 30, day: 16);

    await replan(
      appState,
      now: () => ringDay,
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async => [_meetingAt(eventDay, id: 'evt-1')],
    );

    expect(appState.pendingDayValues['2026-03-16'],
        eventDay.millisecondsSinceEpoch);
  });

  test('ignoring one event on a day with two events leaves the other in '
      'charge', () async {
    final appState = await _freshAppState();
    final ringDay = _utc(0, 0, day: 10);
    final earlier = _utc(6, 0, day: 16);
    final later = _utc(9, 0, day: 16);
    appState.setEventIgnored(_meetingAt(earlier, id: 'evt-early'), true);

    await replan(
      appState,
      now: () => ringDay,
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async => [
        _meetingAt(earlier, id: 'evt-early'),
        _meetingAt(later, id: 'evt-late'),
      ],
    );

    expect(appState.pendingDayValues['2026-03-16'],
        later.millisecondsSinceEpoch,
        reason: 'the earlier, ignored event must not be the one that wins '
            '"earliest hardFloor" - the later, non-ignored one should');
  });

  test('un-ignoring restores the hardFloor on the next replan', () async {
    final appState = await _freshAppState();
    final ringDay = _utc(0, 0, day: 10);
    final eventDay = _utc(7, 30, day: 16);
    final meeting = _meetingAt(eventDay, id: 'evt-1');
    appState.setEventIgnored(meeting, true);
    appState.setEventIgnored(meeting, false);

    await replan(
      appState,
      now: () => ringDay,
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async => [meeting],
    );

    expect(appState.pendingDayValues['2026-03-16'],
        eventDay.millisecondsSinceEpoch);
  });
}
