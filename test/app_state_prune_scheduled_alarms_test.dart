import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';

// docs/TODO.md T-141: AppState.setPrunedScheduledAlarms is the "assign and
// persist" half of the fix - the retention policy itself
// (pruneScheduledAlarms) lives in apply_alarms.dart, not here, so AppState
// doesn't have to import scheduling code and break the one-way layering
// every other scheduling file already depends on (it imports AppState, never
// the other way around).

ScheduledAlarm _alarm(DateTime time, {int id = 1}) => ScheduledAlarm(
      time: time,
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('replaces the list and notifies listeners', () async {
    final appState = await _fresh();
    appState.scheduledAlarms = [_alarm(DateTime(2026, 3, 1), id: 1)];
    var notified = false;
    appState.addListener(() => notified = true);

    appState.setPrunedScheduledAlarms([_alarm(DateTime(2026, 3, 10), id: 2)]);

    expect(appState.scheduledAlarms.map((a) => a.id), [2]);
    expect(notified, isTrue);
  });

  test('persists across a restart', () async {
    final first = await _fresh();
    first.scheduledAlarms = [_alarm(DateTime(2026, 3, 1), id: 1)];

    first.setPrunedScheduledAlarms([_alarm(DateTime(2026, 3, 10), id: 2)]);

    final second = AppState();
    await second.initialized;
    expect(second.scheduledAlarms.map((a) => a.id), [2]);
  });

  test('an unchanged list does not spuriously notify', () async {
    final appState = await _fresh();
    final alarms = [_alarm(DateTime(2026, 3, 10), id: 1)];
    appState.scheduledAlarms = alarms;
    var notified = false;
    appState.addListener(() => notified = true);

    appState.setPrunedScheduledAlarms(alarms);

    expect(notified, isFalse);
  });
}
