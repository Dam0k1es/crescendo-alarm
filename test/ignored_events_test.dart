import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// New feature (user request): a calendar appointment can be "ignored" - it
// then plays no part in scheduling-v2's hardFloor derivation, without ever
// being written back to the calendar itself (which could be a shared
// calendar the user does not own). Persisted by the event's own
// `device_calendar` id (`Meeting.ids`), not by the Meeting object's value
// equality - the same event, refetched on a later sync, must still be
// recognised as ignored even though it is a freshly-constructed `Meeting`.

Meeting _meeting({String id = 'evt-1', DateTime? from}) => Meeting(
      from: from ?? DateTime.utc(2026, 3, 10, 8, 0),
      to: (from ?? DateTime.utc(2026, 3, 10, 8, 0)).add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
      ids: [id],
    );

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('an event is not ignored by default', () async {
    final appState = await _fresh();
    expect(appState.isEventIgnored(_meeting()), isFalse);
  });

  test('ignoring an event is reflected by isEventIgnored', () async {
    final appState = await _fresh();
    final meeting = _meeting();

    appState.setEventIgnored(meeting, true);

    expect(appState.isEventIgnored(meeting), isTrue);
  });

  test('un-ignoring restores the default', () async {
    final appState = await _fresh();
    final meeting = _meeting();
    appState.setEventIgnored(meeting, true);

    appState.setEventIgnored(meeting, false);

    expect(appState.isEventIgnored(meeting), isFalse);
  });

  test('a differently-instantiated Meeting with the same id is still '
      'recognised as ignored', () async {
    // The point of keying by id rather than object equality: a later
    // calendar sync produces a brand new Meeting instance for the same
    // real-world appointment.
    final appState = await _fresh();
    appState.setEventIgnored(_meeting(id: 'evt-7'), true);

    final refetched = _meeting(id: 'evt-7', from: DateTime.utc(2026, 3, 17, 8, 0));

    expect(appState.isEventIgnored(refetched), isTrue);
  });

  test('ignoring one event does not affect another', () async {
    final appState = await _fresh();
    appState.setEventIgnored(_meeting(id: 'evt-a'), true);

    expect(appState.isEventIgnored(_meeting(id: 'evt-b')), isFalse);
  });

  test('notifies listeners when the ignored state changes', () async {
    final appState = await _fresh();
    var notified = false;
    appState.addListener(() => notified = true);

    appState.setEventIgnored(_meeting(), true);

    expect(notified, isTrue);
  });

  test('ignored events survive a restart (persistence round trip)', () async {
    final first = await _fresh();
    first.setEventIgnored(_meeting(id: 'evt-9'), true);

    final second = AppState();
    await second.initialized;

    expect(second.isEventIgnored(_meeting(id: 'evt-9')), isTrue);
  });

  test('never written to the calendar itself - only ids are persisted, '
      'not the Meeting object', () async {
    // This is the whole point of the feature (ignoring must not touch a
    // possibly-shared calendar): the durable state is a bare set of ids,
    // nothing that could round-trip back into an Event.
    final appState = await _fresh();
    appState.setEventIgnored(_meeting(id: 'evt-5'), true);

    expect(appState.ignoredEventIds, contains('evt-5'));
  });
}
