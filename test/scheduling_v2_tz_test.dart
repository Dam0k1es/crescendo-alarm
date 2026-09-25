import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/utils.dart';

// docs/TODO.md T-61, levels 1 and 4 of the planned test structure - with the
// infrastructure that had been missing so far: `tz.initializeTimeZones()`
// plus a fixture helper that builds `Meeting.from` the way `device_calendar`
// delivers it in production - as a `tz.TZDateTime` in the **appointment's
// own** zone, not UTC-tagged. That's exactly what the earlier partial fix
// failed on: every fixture used `DateTime.utc(...)`, so it happened to share
// the same frame as the anchor.
//
// Semantics (Option B): every domain-layer value is a real absolute instant,
// and all values carry the same frame (UTC), so the digit-comparing
// arithmetic (`_wallClockDelta`) yields correct differences.

Meeting _meetingInZone(String zone, int year, int month, int day, int hour,
        int minute) =>
    Meeting(
      from: tz.TZDateTime(tz.getLocation(zone), year, month, day, hour, minute),
      to: tz.TZDateTime(
          tz.getLocation(zone), year, month, day, hour + 1, minute),
      isAllDay: false,
      startTimeZone: zone,
      endTimeZone: zone,
    );

const berlinSummer = Duration(hours: 2);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('hardFloor normalizes the frame (T-61, level 1)', () {
    test('the return value is the same instant, but UTC-tagged', () {
      // 09:00 Europe/Berlin (daylight saving) = 07:00 UTC, minus 30min lead time.
      final event = _meetingInZone('Europe/Berlin', 2026, 7, 10, 9, 0);

      final result = hardFloor(
        day: DateTime.utc(2026, 7, 10),
        allEvents: [event],
        deviceUtcOffset: berlinSummer,
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReady: Duration.zero,
      );

      expect(result, isNotNull);
      // The same real moment (FR-16: the appointment doesn't shift)...
      expect(result!.isAtSameMomentAs(DateTime.utc(2026, 7, 10, 6, 30)), isTrue);
      // ...but in the shared frame, so the digit arithmetic is correct.
      expect(result.isUtc, isTrue);
      expect(result.hour, 6);
    });

    test('an appointment in a FOREIGN zone is normalized too', () {
      // 03:00 Asia/Tokyo (+9) = 18:00 UTC the day before; a device in Berlin
      // (+2) assigns it to the local day before (20:00 Berlin).
      final event = _meetingInZone('Asia/Tokyo', 2026, 7, 11, 3, 0);

      final result = hardFloor(
        day: DateTime.utc(2026, 7, 10),
        allEvents: [event],
        deviceUtcOffset: berlinSummer,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );

      expect(result, isNotNull);
      expect(result!.isAtSameMomentAs(DateTime.utc(2026, 7, 10, 18, 0)), isTrue);
      expect(result.isUtc, isTrue);
    });
  });

  group('ΔT across the frame boundary (T-61, level 2 with a real TZDateTime)', () {
    test('distribute computes the local difference, not the digit difference',
        () {
      final event = _meetingInZone('Europe/Berlin', 2026, 7, 10, 9, 0);
      final target = hardFloor(
        day: DateTime.utc(2026, 7, 10),
        allEvents: [event],
        deviceUtcOffset: berlinSummer,
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReady: Duration.zero,
      )!;

      // Anchor as it comes from pendingDayValues in production: 07:00 Berlin = 05:00 UTC.
      final anchor = DateTime.utc(2026, 7, 9, 5, 0);

      final curve = distribute(
        anchor: anchor,
        target: target,
        n: 1,
        maxDailyDelta: const Duration(hours: 12),
      );

      // Locally: 07:00 -> 08:30, so ΔT = +1:30. Before the fix, the digits 5
      // and 8 were compared (ΔT = +3:30) and the result was 2 hours too late.
      expect(
        curve.valuesByDayOffset[1]!
            .isAtSameMomentAs(DateTime.utc(2026, 7, 10, 6, 30)),
        isTrue,
        reason: 'expected 06:30 UTC = 08:30 Berlin, '
            'got ${curve.valuesByDayOffset[1]}',
      );
    });
  });

  group('FR-18 boundary to the alarm plugin (T-61, level 4)', () {
    test('alarmPlatformTime receives the real moment, minute-precise', () {
      // A planned value is a UTC-tagged instant. The plugin receives a local
      // wall-clock time - previously the UTC value's digits were simply
      // interpreted as local, so the alarm rang too early by the device
      // offset.
      final planned = DateTime.utc(2026, 7, 10, 6, 30, 45);

      final platformTime = alarmPlatformTime(planned);

      expect(platformTime.isUtc, isFalse);
      expect(
        platformTime.isAtSameMomentAs(DateTime.utc(2026, 7, 10, 6, 30)),
        isTrue,
        reason: 'the same real moment (seconds truncated), '
            'got $platformTime',
      );
    });

    test('an already-local value stays unchanged (ManualAlarm path)', () {
      final local = DateTime(2026, 7, 10, 6, 30);

      final platformTime = alarmPlatformTime(local);

      expect(platformTime, local);
    });
  });
}
