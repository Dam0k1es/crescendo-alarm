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
