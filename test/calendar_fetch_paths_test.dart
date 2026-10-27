import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Colors;
import 'package:device_calendar_plus/device_calendar_plus.dart' as plus;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';

// docs/TODO.md T-244 (review N2/N4): the two functions that read the device
// calendar had no test for their error paths - the plugin is a hard singleton -
// and a refused permission left no trace that told it from "no calendars".
// The two seams below replace only the plugin calls; the filtering,
// cancellation, windowing and outcome logic under test is production code.

plus.Calendar _cal(String id, {String? colorHex}) =>
    plus.Calendar(id: id, name: id, readOnly: true, colorHex: colorHex);

plus.Event _event(
  String id, {
  required DateTime start,
  required DateTime end,
  plus.EventStatus status = plus.EventStatus.confirmed,
  String calendarId = 'a',
}) =>
    plus.Event(
      eventId: id,
      instanceId: id,
      calendarId: calendarId,
      title: id,
      startDate: start,
      endDate: end,
      isAllDay: false,
      availability: plus.EventAvailability.busy,
      status: status,
      isRecurring: false,
    );

plus.DeviceCalendarException _denied() => const plus.DeviceCalendarException(
    errorCode: plus.DeviceCalendarError.permissionDenied, message: 'denied');

Future<AppState> _appState() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

int _outcome() => Diag.records.last.fields[DiagField.outcome]!;

final _start = DateTime(2026, 7, 6);
final _end = DateTime(2026, 7, 13);
DateTime _at(int day, int hour) => DateTime(2026, 7, day, hour);

void main() {
  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Diag.resetForTest();
    await Diag.init(isolate: LogIsolate.main, enabled: true);
    appState = await _appState();
    calendars = [];
  });

  tearDown(() {
    calendars = [];
    resetCalendarSourcesForTest();
  });

  group('fetchMeetingsUncached', () {
    test('hands the half-open window and the calendar id to the plugin',
        () async {
      calendars = [_cal('a')];
      final seen = <List<Object>>[];
      listEventsFromDevice = (start, end, id) async {
        seen.add([start, end, id]);
        return [];
      };

      await fetchMeetingsUncached(appState, _start, _end);

      expect(seen, [
        [_start, _end, 'a']
      ]);
    });

    test('drops a cancelled occurrence and keeps the others', () async {
      calendars = [_cal('a')];
      listEventsFromDevice = (s, e, id) async => [
            _event('ok', start: _at(7, 9), end: _at(7, 10)),
            _event('gone',
                start: _at(8, 9),
                end: _at(8, 10),
                status: plus.EventStatus.canceled),
          ];

      final meetings = await fetchMeetingsUncached(appState, _start, _end);

      expect(meetings.map((m) => m.ids.single), ['ok']);
    });

    test('one failing calendar costs only its own events (partialErrors)',
        () async {
      calendars = [_cal('a'), _cal('b')];
      listEventsFromDevice = (s, e, id) async => id == 'a'
          ? throw StateError('boom')
          : [_event('b1', start: _at(7, 9), end: _at(7, 10), calendarId: 'b')];

      final meetings = await fetchMeetingsUncached(appState, _start, _end);

      expect(meetings.map((m) => m.ids.single), ['b1']);
      expect(_outcome(), CalendarOutcome.partialErrors.code);
    });

    test('every selected calendar failing reads as retrieveThrew', () async {
      calendars = [_cal('a'), _cal('b')];
      listEventsFromDevice = (s, e, id) async => throw StateError('boom');

      final meetings = await fetchMeetingsUncached(appState, _start, _end);

      expect(meetings, isEmpty);
      expect(_outcome(), CalendarOutcome.retrieveThrew.code);
    });

    test('a clean read is ok', () async {
      calendars = [_cal('a')];
      listEventsFromDevice = (s, e, id) async => [];

      await fetchMeetingsUncached(appState, _start, _end);

      expect(_outcome(), CalendarOutcome.ok.code);
    });

    test('a refused calendar permission is told apart from "no calendars"',
        () async {
      listCalendarsFromDevice = () async => throw _denied();

      final meetings = await fetchMeetingsUncached(appState, _start, _end);

      expect(meetings, isEmpty);
      expect(_outcome(), CalendarOutcome.permissionDenied.code);
    });

    test('any other failure to list the calendars reads as initThrew',
        () async {
      listCalendarsFromDevice = () async => throw StateError('boom');

      await fetchMeetingsUncached(appState, _start, _end);

      expect(_outcome(), CalendarOutcome.initThrew.code);
    });

    test('a device with no calendars still reads as noCalendars', () async {
      listCalendarsFromDevice = () async => [];

      await fetchMeetingsUncached(appState, _start, _end);

      expect(_outcome(), CalendarOutcome.noCalendars.code);
    });

    test('a permission failure does not stick once the grant is there',
        () async {
      listCalendarsFromDevice = () async => throw _denied();
      await fetchMeetingsUncached(appState, _start, _end);
      expect(_outcome(), CalendarOutcome.permissionDenied.code);

      listCalendarsFromDevice = () async => [_cal('a')];
      listEventsFromDevice = (s, e, id) async => [];
      await fetchMeetingsUncached(appState, _start, _end);

      expect(_outcome(), CalendarOutcome.ok.code);
    });

    test('deselecting every calendar reads as noCalendars, not as a failure',
        () async {
      calendars = [_cal('a')];
      appState.setCalendarSelected('a', false);
      listEventsFromDevice = (s, e, id) async => fail('must not be read');

      await fetchMeetingsUncached(appState, _start, _end);

      expect(_outcome(), CalendarOutcome.noCalendars.code);
    });
  });

  group('getCalendarEntries', () {
    test('skips a failing calendar and still returns the others', () async {
      calendars = [_cal('a'), _cal('b')];
      listEventsFromDevice = (s, e, id) async => id == 'a'
          ? throw StateError('boom')
          : [_event('b1', start: _at(7, 9), end: _at(7, 10), calendarId: 'b')];

      final meetings = await getCalendarEntries(appState, _start, _end);

      expect(meetings.map((m) => m.ids.single), ['b1']);
    });

    test('drops cancelled occurrences, as the scheduling read does', () async {
      calendars = [_cal('a')];
      listEventsFromDevice = (s, e, id) async => [
            _event('ok', start: _at(7, 9), end: _at(7, 10)),
            _event('gone',
                start: _at(8, 9),
                end: _at(8, 10),
                status: plus.EventStatus.canceled),
          ];

      final meetings = await getCalendarEntries(appState, _start, _end);

      expect(meetings.map((m) => m.ids.single), ['ok']);
    });

    test('draws each event in its calendar colour, falling back to green',
        () async {
      calendars = [_cal('a', colorHex: '#0000FF'), _cal('b')];
      listEventsFromDevice = (s, e, id) async => [
            _event('$id-1', start: _at(7, 9), end: _at(7, 10), calendarId: id),
          ];

      final meetings = await getCalendarEntries(appState, _start, _end);

      expect(meetings.map((m) => m.background),
          [const Color(0xFF0000FF), Colors.green]);
    });

    test('an event already in AppState.meetings is not returned twice',
        () async {
      calendars = [_cal('a')];
      listEventsFromDevice =
          (s, e, id) async => [_event('e1', start: _at(7, 9), end: _at(7, 10))];
      final first = await getCalendarEntries(appState, _start, _end);
      appState.meetings = [...first];

      final second = await getCalendarEntries(appState, _start, _end);

      expect(second, isEmpty);
    });
  });
}
