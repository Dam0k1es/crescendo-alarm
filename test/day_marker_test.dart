import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/models/scheduling/day_marker.dart';

// docs/TODO.md T-76 (and T-74d, whose fix was incomplete): day arithmetic must
// run over date fields, not over absolute durations. Tested with
// `tz.TZDateTime` in a zone with a real transition, so the test reproduces
// independently of the test machine's time zone - `DateTime.now()` is UTC+0
// on the dev VM and would never have shown this bug class.

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location berlin;
  setUp(() => berlin = tz.getLocation('Europe/Berlin'));

  group('dayDistance', () {
    test('counts calendar days correctly across the spring transition', () {
      // 2026-03-29 is the transition to daylight saving in Europe/Berlin;
      // that day only has 23 hours.
      final before = tz.TZDateTime(berlin, 2026, 3, 27);
      final after = tz.TZDateTime(berlin, 2026, 4, 3);

      expect(dayDistance(after, before), 7);
      // Proof that the naive way is actually wrong here (otherwise this
      // test would be worthless, since it wouldn't guard anything):
      expect(after.difference(before).inDays, 6);
    });

    test('also counts correctly across the autumn transition', () {
      final before = tz.TZDateTime(berlin, 2026, 10, 24);
      final after = tz.TZDateTime(berlin, 2026, 10, 26);

      expect(dayDistance(after, before), 2);
    });

    test('is sign-correct and frame-crossing', () {
      expect(dayDistance(DateTime.utc(2026, 3, 27), DateTime.utc(2026, 4, 3)),
          -7);
      expect(
          dayDistance(
              tz.TZDateTime(berlin, 2026, 4, 3), DateTime.utc(2026, 4, 1)),
          2);
    });
  });

  group('dayMarker', () {
    test('stays on the same calendar date across the transition', () {
      final start = DateTime.utc(2026, 3, 28);
      final marker = dayMarker(start, 2);

      expect(marker, DateTime.utc(2026, 3, 30));
      expect(marker.isUtc, isTrue);
    });

    test('preserves the local frame and normalizes month overruns', () {
      final marker = dayMarker(DateTime(2026, 3, 30), 5);

      expect(marker.isUtc, isFalse);
      expect(marker.year, 2026);
      expect(marker.month, 4);
      expect(marker.day, 4);
    });

    test('seven consecutive markers yield seven different days',
        () {
      // Exactly the regression case from T-74d: with `add(Duration(days: i))`,
      // two window days collided on the same isoDate key.
      final start = DateTime(2026, 3, 28);
      final window = List.generate(7, (i) => dayMarker(start, i));

      expect(window.map(isoDate).toSet().length, 7);
    });
  });

  group('midnight / isoDate', () {
    test('midnight truncates the time of day and preserves the frame', () {
      expect(midnight(DateTime.utc(2026, 3, 28, 17, 45)),
          DateTime.utc(2026, 3, 28));
      expect(midnight(DateTime(2026, 3, 28, 17, 45)).isUtc, isFalse);
    });

    test('isoDate is zero-padded', () {
      expect(isoDate(DateTime.utc(2026, 4, 3)), '2026-04-03');
    });
  });

  group('leap day and year boundary (T-124)', () {
    // The classic hand-rolled day-of-year calculation (a cumulative month
    // table plus `(a.year - b.year) * 365`) yields one day too few for 2028
    // across February 29. Proven: such a mutation in `dayDistance` leaves
    // **all** sixteen test files green, this file included - even though
    // this file is exactly the one responsible for this arithmetic. The leap
    // day is the only configuration in which it becomes visible.

    test('across February 29', () {
      expect(dayDistance(DateTime.utc(2028, 3, 1), DateTime.utc(2028, 2, 28)), 2,
          reason: '2028 is a leap year - Feb 29 lies in between');
      expect(dayDistance(DateTime.utc(2027, 3, 1), DateTime.utc(2027, 2, 28)), 1,
          reason: '2027 is not');
    });

    test('a window across the leap day has seven different days', () {
      final start = DateTime.utc(2028, 2, 26);
      final window = List.generate(7, (i) => dayMarker(start, i));
      expect(window.map(isoDate).toSet().length, 7);
      expect(window.map(isoDate), contains('2028-02-29'));
    });

    test('across the year boundary', () {
      expect(dayDistance(DateTime.utc(2027, 1, 2), DateTime.utc(2026, 12, 30)), 3);
      final window = List.generate(7, (i) => dayMarker(DateTime.utc(2026, 12, 29), i));
      expect(window.map(isoDate).toSet().length, 7);
      expect(window.map(isoDate), contains('2027-01-01'));
    });
  });
}
