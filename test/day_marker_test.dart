import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/models/scheduling/day_marker.dart';

// docs/TODO.md T-76 (und T-74d, dessen Fix unvollständig war): Tagesarithmetik
// muss über Datumsfelder laufen, nicht über absolute Dauern. Getestet mit
// `tz.TZDateTime` in einer Zone mit echter Umstellung, damit der Test
// unabhängig von der Zeitzone der Testmaschine reproduziert - `DateTime.now()`
// ist auf der Entwicklungs-VM UTC+0 und hätte die Klasse von Fehlern nie
// gezeigt.

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location berlin;
  setUp(() => berlin = tz.getLocation('Europe/Berlin'));

  group('dayDistance', () {
    test('zählt Kalendertage über die Frühjahrsumstellung korrekt', () {
      // 2026-03-29 ist in Europe/Berlin die Umstellung auf Sommerzeit; der Tag
      // hat nur 23 Stunden.
      final before = tz.TZDateTime(berlin, 2026, 3, 27);
      final after = tz.TZDateTime(berlin, 2026, 4, 3);

      expect(dayDistance(after, before), 7);
      // Der Nachweis, dass der naive Weg hier tatsächlich falsch liegt (sonst
      // wäre dieser Test wertlos, weil er nichts absichert):
      expect(after.difference(before).inDays, 6);
    });

    test('zählt auch über die Herbstumstellung korrekt', () {
      final before = tz.TZDateTime(berlin, 2026, 10, 24);
      final after = tz.TZDateTime(berlin, 2026, 10, 26);

      expect(dayDistance(after, before), 2);
    });

    test('ist vorzeichenrichtig und frame-übergreifend', () {
      expect(dayDistance(DateTime.utc(2026, 3, 27), DateTime.utc(2026, 4, 3)),
          -7);
      expect(
          dayDistance(
              tz.TZDateTime(berlin, 2026, 4, 3), DateTime.utc(2026, 4, 1)),
          2);
    });
  });

  group('dayMarker', () {
    test('bleibt über die Umstellung auf demselben Kalenderdatum', () {
      final start = DateTime.utc(2026, 3, 28);
      final marker = dayMarker(start, 2);

      expect(marker, DateTime.utc(2026, 3, 30));
      expect(marker.isUtc, isTrue);
    });

    test('erhält den lokalen Frame und normalisiert Monatsüberläufe', () {
      final marker = dayMarker(DateTime(2026, 3, 30), 5);

      expect(marker.isUtc, isFalse);
      expect(marker.year, 2026);
      expect(marker.month, 4);
      expect(marker.day, 4);
    });

    test('sieben aufeinanderfolgende Marker ergeben sieben verschiedene Tage',
        () {
      // Genau der Regressionsfall von T-74d: mit `add(Duration(days: i))`
      // kollidierten zwei Fenstertage auf demselben isoDate-Schlüssel.
      final start = DateTime(2026, 3, 28);
      final window = List.generate(7, (i) => dayMarker(start, i));

      expect(window.map(isoDate).toSet().length, 7);
    });
  });

  group('midnight / isoDate', () {
    test('midnight schneidet die Uhrzeit ab und erhält den Frame', () {
      expect(midnight(DateTime.utc(2026, 3, 28, 17, 45)),
          DateTime.utc(2026, 3, 28));
      expect(midnight(DateTime(2026, 3, 28, 17, 45)).isUtc, isFalse);
    });

    test('isoDate ist nullgepolstert', () {
      expect(isoDate(DateTime.utc(2026, 4, 3)), '2026-04-03');
    });
  });
}
