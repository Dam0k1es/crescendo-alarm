import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

// docs/TODO.md T-89: der Ereignis-Logger soll aus echter Nutzung diagnostisch
// verwertbares Feedback liefern, OHNE personenbezogene Daten zu erfassen.
//
// Die tragende Entwurfsentscheidung ist, dass diese Freiheit *strukturell*
// erzwungen wird und nicht disziplinarisch: die Aufzeichnungs-API nimmt keinen
// einzigen String. Damit gibt es keinen Kanal, durch den ein Termintitel, ein
// Kalendername, eine Exception-Nachricht oder der QR-Deaktivierungscode
// hineingeraten koennte - was nicht darstellbar ist, kann nicht austreten.
//
// Dieser Test prueft genau diese Eigenschaft am Quelltext, weil sie sich nicht
// aus Werten ableiten laesst: ein wertbasierter Test wuerde nur die heute
// bekannten Lecks fangen, nicht den naechsten neu hinzugefuegten Parameter.

/// Der Quelltext des Loggers. Bewusst pro Test frisch gelesen und **nicht**
/// in `setUpAll` mit `expect` vorbereitet: eine Zusicherung in `setUpAll`
/// laesst den Test-Harness haengen, statt sauber rot zu werden (hier real
/// passiert - der Lauf blieb minutenlang in `(setUpAll)` stehen).
String _source() => File('lib/utils/diag/diag_log.dart').readAsStringSync();

/// Die oeffentliche Fassade: alles ab dem Marker. Darueber liegen die
/// Enum-Definitionen und die privaten Reduktionsfunktionen, in denen Strings
/// (Doc-Kommentare, Prefs-Schluessel) legitim vorkommen.
String _publicApi() {
  const marker = '// == PUBLIC RECORDING API ==';
  final source = _source();
  final index = source.indexOf(marker);
  if (index < 0) {
    fail('Der Marker "$marker" grenzt die oeffentliche Fassade ab - '
        'ohne ihn kann dieser Test nicht pruefen, was er pruefen soll.');
  }
  return source.substring(index);
}

void main() {

  group('strukturelle PII-Freiheit', () {
    test('keine oeffentliche Methode nimmt einen String', () {
      // Fasst Parameterlisten der Fassade zusammen und sucht nach String-Typen.
      final offenders = <String>[];
      for (final match
          in RegExp(r'static\s+\w+\s+(\w+)\(([^)]*)\)').allMatches(_publicApi())) {
        final name = match.group(1)!;
        final params = match.group(2)!;
        if (RegExp(r'\bString\b').hasMatch(params)) {
          offenders.add('$name($params)');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Ein String-Parameter ist ein PII-Kanal. Nimm ein Enum, '
              'einen Zaehler oder einen Type:\n${offenders.join('\n')}');
    });

    test('die Senke haelt keine Strings, nur Zahlen', () {
      // DiagRecord.encode() ist die einzige Stelle, an der ein Record die
      // In-Memory-Struktur verlaesst. Sie muss List<int> liefern.
      expect(_source(), contains('List<int> encode()'),
          reason: 'Ein Record wird als reine Zahlenliste kodiert - so kann '
              'kein Freitext in SharedPreferences landen.');
    });

    test('kein debugPrint und kein print im Logger selbst', () {
      // Sonst waere der PII-freie Logger seinerseits ein Log-Leck, und im
      // Hintergrund-Isolate griffe main.darts kReleaseMode-Guard nicht.
      expect(RegExp(r'(?<![A-Za-z0-9_])debugPrint\(').hasMatch(_source()), isFalse);
      expect(RegExp(r'(?<![A-Za-z0-9_.])print\(').hasMatch(_source()), isFalse);
    });

    test('keine Uhrablesung im Logger', () {
      // Reihenfolge kommt aus einem Zaehler, Dauern aus Stopwatch. Ein
      // Zeitstempel pro Ereignis waere zusammen mit den Weckereignissen ein
      // Schlafmuster - und damit identifizierend ohne jeden Namen.
      expect(_source().contains('DateTime.now()'), isFalse,
          reason: 'Kein DateTime.now() im Logger - Reihenfolge ueber bootSeq/'
              'seq, Grobzeit ueber Stopwatch-Buckets.');
      expect(_source().contains('DateTime.timestamp()'), isFalse);
    });

    test('int-Parameter sind nur Zaehlungen und relative Tage', () {
      // Alles, was aus einer Uhr stammt, betritt das Log ausschliesslich als
      // Bucket-Enum. Ein int namens "...Minutes"/"...Ms"/"...Epoch" waere ein
      // Rohwert und damit ein Rueckweg zur Wanduhr.
      final offenders = <String>[];
      for (final match
          in RegExp(r'required\s+int\s+(\w+)').allMatches(_publicApi())) {
        final name = match.group(1)!;
        if (RegExp(r'(Minutes|Ms|Millis|Epoch|Time|Date|Hour|Clock)$')
            .hasMatch(name)) {
          offenders.add(name);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Diese int-Parameter tragen einen Uhrwert. Reduziere sie '
              'vorher auf ein Bucket-Enum:\n${offenders.join(', ')}');
    });
  });

  group('Kodierung und Grenzen', () {
    test('Ereignis- und Feldcodes sind stabil und eindeutig', () {
      // Der Index einer Dart-Enum verschiebt sich beim Umsortieren; ein
      // exportiertes Log muss aber auch von einer anderen App-Version noch
      // lesbar sein. Deshalb explizite Codes - und die muessen eindeutig sein.
      final eventCodes = DiagEvent.values.map((e) => e.code).toList();
      expect(eventCodes.toSet().length, eventCodes.length,
          reason: 'doppelter DiagEvent-Code');
      final fieldCodes = DiagField.values.map((f) => f.code).toList();
      expect(fieldCodes.toSet().length, fieldCodes.length,
          reason: 'doppelter DiagField-Code');
    });

    test('der Ringpuffer ist nach oben begrenzt', () {
      // Lehre aus T-82: unbegrenztes Wachstum ist hier doppelt schaedlich -
      // es frisst Speicher UND macht aus dem Log ein Langzeitprofil.
      expect(Diag.capacity, lessThanOrEqualTo(1024));
      expect(Diag.capacity, greaterThanOrEqualTo(128));
    });
  });
}
