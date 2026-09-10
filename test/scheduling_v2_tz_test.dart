import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/utils.dart';

// docs/TODO.md T-61, Ebene 1 und 4 der geplanten Teststruktur - mit der
// Infrastruktur, die bisher fehlte: `tz.initializeTimeZones()` plus ein
// Fixture-Helper, der `Meeting.from` so baut, wie `device_calendar` es in
// Produktion liefert - als `tz.TZDateTime` in der **termin-eigenen** Zone,
// nicht UTC-getaggt. Genau daran ist der frühere Teilfix gescheitert: alle
// Fixtures nutzten `DateTime.utc(...)`, also zufällig denselben Frame wie der
// Anker.
//
// Semantik (Option B): jeder Wert der Domänenschicht ist ein echter absoluter
// Instant, und alle Werte tragen denselben Frame (UTC), damit die
// ziffernvergleichende Arithmetik (`_wallClockDelta`) korrekte Differenzen
// liefert.

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

  group('hardFloor normalisiert den Frame (T-61, Ebene 1)', () {
    test('Rückgabewert ist derselbe Instant, aber UTC-getaggt', () {
      // 09:00 Europe/Berlin (Sommerzeit) = 07:00 UTC, minus 30min Vorlauf.
      final event = _meetingInZone('Europe/Berlin', 2026, 7, 10, 9, 0);

      final result = hardFloor(
        day: DateTime.utc(2026, 7, 10),
        allEvents: [event],
        deviceUtcOffset: berlinSummer,
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReady: Duration.zero,
      );

      expect(result, isNotNull);
      // Derselbe reale Moment (FR-16: der Termin verschiebt sich nicht)...
      expect(result!.isAtSameMomentAs(DateTime.utc(2026, 7, 10, 6, 30)), isTrue);
      // ...aber im gemeinsamen Frame, damit die Ziffernarithmetik stimmt.
      expect(result.isUtc, isTrue);
      expect(result.hour, 6);
    });

    test('ein Termin in einer FREMDEN Zone wird ebenfalls normalisiert', () {
      // 03:00 Asia/Tokyo (+9) = 18:00 UTC am Vortag; Gerät in Berlin (+2)
      // ordnet ihn dem lokalen Vortag (20:00 Berlin) zu.
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

  group('ΔT über die Frame-Grenze (T-61, Ebene 2 mit echtem TZDateTime)', () {
    test('distribute rechnet die lokale Differenz, nicht die Ziffern-Differenz',
        () {
      final event = _meetingInZone('Europe/Berlin', 2026, 7, 10, 9, 0);
      final target = hardFloor(
        day: DateTime.utc(2026, 7, 10),
        allEvents: [event],
        deviceUtcOffset: berlinSummer,
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReady: Duration.zero,
      )!;

      // Anker wie in Produktion aus pendingDayValues: 07:00 Berlin = 05:00 UTC.
      final anchor = DateTime.utc(2026, 7, 9, 5, 0);

      final curve = distribute(
        anchor: anchor,
        target: target,
        n: 1,
        maxDailyDelta: const Duration(hours: 12),
      );

      // Lokal: 07:00 -> 08:30, also ΔT = +1:30. Vor dem Fix wurden die Ziffern
      // 5 und 8 verglichen (ΔT = +3:30) und das Ergebnis lag 2 Stunden zu spät.
      expect(
        curve.valuesByDayOffset[1]!
            .isAtSameMomentAs(DateTime.utc(2026, 7, 10, 6, 30)),
        isTrue,
        reason: 'erwartet 06:30 UTC = 08:30 Berlin, '
            'bekommen ${curve.valuesByDayOffset[1]}',
      );
    });
  });

  group('FR-18-Grenze zum Alarm-Plugin (T-61, Ebene 4)', () {
    test('alarmPlatformTime erhält den realen Moment, minutengenau', () {
      // Ein geplanter Wert ist ein UTC-getaggter Instant. Das Plugin bekommt
      // eine lokale Wall-Clock-Zeit - vorher wurden dafür einfach die Ziffern
      // des UTC-Werts als lokal interpretiert, der Alarm klingelte also um den
      // Geräte-Versatz zu früh.
      final planned = DateTime.utc(2026, 7, 10, 6, 30, 45);

      final platformTime = alarmPlatformTime(planned);

      expect(platformTime.isUtc, isFalse);
      expect(
        platformTime.isAtSameMomentAs(DateTime.utc(2026, 7, 10, 6, 30)),
        isTrue,
        reason: 'derselbe reale Moment (Sekunden abgeschnitten), '
            'bekommen $platformTime',
      );
    });

    test('ein bereits lokaler Wert bleibt unverändert (ManualAlarm-Pfad)', () {
      final local = DateTime(2026, 7, 10, 6, 30);

      final platformTime = alarmPlatformTime(local);

      expect(platformTime, local);
    });
  });
}
