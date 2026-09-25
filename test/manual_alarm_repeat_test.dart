import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm_enable.dart';

// docs/TODO.md T-14: `repeatOnDays` is editable and persisted but was never
// consulted when deciding when a manual alarm actually fires - the selector
// promised a weekly pattern while the alarm behaved as one-shot
// (today-or-tomorrow, regardless of which days were selected).
//
// `nextManualOccurrence` is the single function both `AppState._getAlarmTime`
// (creating an alarm) and `applyManualAlarmEnabled` (the FR-21 toggle) call,
// specifically so the two can never resolve the same alarm to different days
// - see that function's own doc comment. Extending its signature, rather than
// adding a second day-aware function beside it, keeps that guarantee.

Map<DayOfWeek, bool> _only(List<DayOfWeek> days) => {
      for (final day in DayOfWeek.values) day: days.contains(day),
    };

const _allDays = {
  DayOfWeek.monday: true,
  DayOfWeek.tuesday: true,
  DayOfWeek.wednesday: true,
  DayOfWeek.thursday: true,
  DayOfWeek.friday: true,
  DayOfWeek.saturday: true,
  DayOfWeek.sunday: true,
};

void main() {
  group('every day selected behaves like the old today-or-tomorrow rule', () {
    test('still ahead today -> today', () {
      final now = DateTime(2026, 3, 10, 6, 0); // a Tuesday
      final result =
          nextManualOccurrence(const TimeOfDay(hour: 7, minute: 30), now, _allDays);
      expect(result, DateTime(2026, 3, 10, 7, 30));
    });

    test('already past today -> tomorrow', () {
      final now = DateTime(2026, 3, 10, 6, 0);
      final result =
          nextManualOccurrence(const TimeOfDay(hour: 5, minute: 0), now, _allDays);
      expect(result, DateTime(2026, 3, 11, 5, 0));
    });
  });

  test('a single weekday selected skips every other day', () {
    // 2026-03-10 is a Tuesday; the alarm only repeats on Friday.
    final now = DateTime(2026, 3, 10, 6, 0);
    final result = nextManualOccurrence(
      const TimeOfDay(hour: 7, minute: 0),
      now,
      _only([DayOfWeek.friday]),
    );
    expect(result, DateTime(2026, 3, 13, 7, 0),
        reason: '2026-03-13 is the next Friday');
  });

  test('today is selected but its time has already passed -> next week',
      () {
    // Tuesday, 06:00 "now"; the alarm is set for 05:00 and only repeats on
    // Tuesdays - today's slot is gone, so it must wrap to next Tuesday, not
    // silently fall back to "tomorrow" (which honouring repeatOnDays
    // strictly would skip, since Wednesday isn't selected).
    final now = DateTime(2026, 3, 10, 6, 0);
    final result = nextManualOccurrence(
      const TimeOfDay(hour: 5, minute: 0),
      now,
      _only([DayOfWeek.tuesday]),
    );
    expect(result, DateTime(2026, 3, 17, 5, 0));
  });

  test('weekday selection is honoured across a week boundary', () {
    // Only Monday and Thursday selected; "now" is Friday, after both.
    final now = DateTime(2026, 3, 13, 12, 0); // a Friday
    final result = nextManualOccurrence(
      const TimeOfDay(hour: 7, minute: 0),
      now,
      _only([DayOfWeek.monday, DayOfWeek.thursday]),
    );
    expect(result, DateTime(2026, 3, 16, 7, 0),
        reason: 'the next Monday, not the passed Thursday');
  });

  // docs/TODO.md T-181 (maintainer request): "prüfe ob es tests gibt die
  // manuelle alarme darauf prüfen, ob sie bei z. B. Auswahl von Sonntag nur
  // einen, oder alle Sonntage klingelt" - the existing cases above only ever
  // call nextManualOccurrence ONCE per test, proving the next candidate is
  // picked correctly but never proving the alarm actually keeps recurring
  // across multiple weeks rather than only ever firing on the first match.
  group('a single selected weekday recurs indefinitely, not just once', () {
    test('selecting only Sunday rings every Sunday, chained across 5 weeks',
        () {
      // 2026-03-08 is a Sunday. Each iteration simulates the alarm having
      // just rung and been dismissed a minute later - exactly what
      // Handler.onAlarmHandled's re-arm does in production.
      var now = DateTime(2026, 3, 8, 7, 1);
      final sundaysOnly = _only([DayOfWeek.sunday]);
      final occurrences = <DateTime>[];

      for (var i = 0; i < 5; i++) {
        final next = nextManualOccurrence(
            const TimeOfDay(hour: 7, minute: 0), now, sundaysOnly);
        occurrences.add(next);
        now = next.add(const Duration(minutes: 1));
      }

      for (final date in occurrences) {
        expect(date.weekday, DateTime.sunday,
            reason: 'every occurrence must land on the one selected day');
      }
      for (var i = 1; i < occurrences.length; i++) {
        expect(occurrences[i].difference(occurrences[i - 1]),
            const Duration(days: 7),
            reason: 'a single selected weekday must repeat every week - '
                'ringing only once (or skipping/repeating a week) would '
                'silently break the "repeat on" promise');
      }
    });

    test(
        'the actual FR-21 re-arm path (applyManualAlarmEnabled) repeats a '
        'Sunday-only alarm every week, not just once', () async {
      // Exercises the real function Handler.onAlarmHandled's re-arm goes
      // through (via AppState.setManualAlarmEnabled), not just the pure
      // date-math helper - a regression in applyManualAlarmEnabled's own
      // wiring (e.g. its own `now` handling) would not be caught by the
      // nextManualOccurrence-only test above.
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        repeatOnDays: _only([DayOfWeek.sunday]),
      );
      var now = DateTime(2026, 3, 8, 7, 1);
      final armedDates = <DateTime>[];

      for (var i = 0; i < 3; i++) {
        final applied = await applyManualAlarmEnabled(
          alarm: alarm,
          enabled: true,
          now: now,
          armAlarm: (a, at) async => armedDates.add(at),
          stopAlarm: (id) async {},
        );
        expect(applied, isTrue);
        now = armedDates.last.add(const Duration(minutes: 1));
      }

      expect(armedDates.every((d) => d.weekday == DateTime.sunday), isTrue);
      for (var i = 1; i < armedDates.length; i++) {
        expect(armedDates[i].difference(armedDates[i - 1]),
            const Duration(days: 7));
      }
    });
  });

  test('no day selected at all falls back to today-or-tomorrow rather than '
      'never arming', () {
    // Not a case the UI can normally reach (creation pre-selects the current
    // day), but a persisted alarm could still end up here - an inert switch
    // that claims to be armed forever would be worse than ignoring the
    // (empty) selection.
    final now = DateTime(2026, 3, 10, 6, 0);
    final result = nextManualOccurrence(
      const TimeOfDay(hour: 7, minute: 30),
      now,
      _only(const []),
    );
    expect(result, DateTime(2026, 3, 10, 7, 30));
  });
}
