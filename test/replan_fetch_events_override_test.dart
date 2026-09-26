import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-194: the E2E suite (integration_test/app_test.dart) injects
// its calendar through `fetchEvents` on ONE checkpoint call - but the app
// under test starts checkpoints of its own that never receive it: the
// open-sync `manualSync` in main.dart (queued only after its calendar I/O
// finishes, so it can land AFTER the test's own plan), and the resume a
// ringing alarm's full-screen intent triggers. Those read the emulator's real,
// empty calendar and replan the injected week away ("removed 7, added 0") -
// exactly what failed "T-64: dismissing a ringing alarm leaves the planned
// week registered" twice on master run 36249699023 while the product itself
// behaved correctly. A process-wide override lets the harness make the
// injected calendar what EVERY checkpoint sees, the way a real device's
// calendar would be.

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

Meeting _meetingAt(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
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
  tearDown(() => debugFetchEventsOverride = null);

  test('a replan with no fetchEvents argument reads debugFetchEventsOverride',
      () async {
    final appState = await _freshAppState();
    final eventDay = _utc(7, 30, day: 16);
    debugFetchEventsOverride = (start, end) async => [_meetingAt(eventDay)];

    await replan(
      appState,
      now: () => _utc(0, 0, day: 10),
      deviceUtcOffset: Duration.zero,
    );

    expect(appState.pendingDayValues['2026-03-16'],
        eventDay.millisecondsSinceEpoch,
        reason: 'the override is the calendar every checkpoint without its '
            'own fetchEvents must see - otherwise the app\'s own open-sync '
            'replans the E2E suite\'s injected week away');
  });

  test('an explicit fetchEvents argument still wins over the override',
      () async {
    // Counter-test: the override is a fallback for the DEFAULT source, not a
    // hijack of callers that pass their own.
    final appState = await _freshAppState();
    final explicitDay = _utc(7, 30, day: 16);
    debugFetchEventsOverride =
        (start, end) async => [_meetingAt(_utc(9, 0, day: 16))];

    await replan(
      appState,
      now: () => _utc(0, 0, day: 10),
      deviceUtcOffset: Duration.zero,
      fetchEvents: (start, end) async => [_meetingAt(explicitDay)],
    );

    expect(appState.pendingDayValues['2026-03-16'],
        explicitDay.millisecondsSinceEpoch);
  });

  test('null by default - production reads the real calendar', () {
    expect(debugFetchEventsOverride, isNull);
  });
}
