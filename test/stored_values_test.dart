import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/stored_values.dart';

// docs/TODO.md T-83: dieselbe `Map<String, int?>` (AppState.pendingDayValues)
// wurde an fünf Stellen gelesen, dreimal UTC-getaggt und zweimal ohne Tag.
// Beides war korrekt - die Domänenschicht verlangt UTC-Tagging (ihre
// Arithmetik vergleicht Ziffernfelder), Anzeige und ScheduledAlarm.title
// (formatDateTime) verlangen lokale Ziffern. Genau deshalb war es gefährlich:
// ein Vereinheitlichen "für Konsistenz" hätte Anzeige und Alarmtitel still um
// den Geräteversatz verschoben. Zwei benannte Konverter machen die Absicht an
// jeder Aufrufstelle sichtbar.

void main() {
  final instant = DateTime.utc(2026, 3, 11, 6, 30);
  final millis = instant.millisecondsSinceEpoch;

  group('instantFromStored (Domänenschicht)', () {
    test('ist UTC-getaggt', () {
      final value = instantFromStored(millis)!;

      expect(value.isUtc, isTrue);
      expect(value, instant);
    });

    test('null bleibt null (Lückentag/Sicherheitsventil)', () {
      expect(instantFromStored(null), isNull);
    });
  });

  group('localFromStored (Plattform und Anzeige)', () {
    test('ist lokal getaggt', () {
      final value = localFromStored(millis)!;

      expect(value.isUtc, isFalse);
    });

    test('null bleibt null', () {
      expect(localFromStored(null), isNull);
    });
  });

  test('beide bezeichnen denselben realen Moment', () {
    // Der Unterschied ist ausschließlich das Tagging, nie der Zeitpunkt - das
    // ist die Eigenschaft, auf die sich beide Aufrufseiten verlassen.
    expect(
      localFromStored(millis)!.isAtSameMomentAs(instantFromStored(millis)!),
      isTrue,
    );
  });

  test('toStored ist die Umkehrung, frame-unabhängig', () {
    expect(toStored(instant), millis);
    expect(toStored(instant.toLocal()), millis);
    expect(toStored(null), isNull);
  });
}
