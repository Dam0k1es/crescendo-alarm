import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-89: PII-Freiheit der Log-Ausgaben wird strukturell geprueft,
// nicht durch Disziplin. Ein unabhaengiger Audit fand fuenf kritische Lecks
// (der QR-Deaktivierungscode an drei Stellen, der Kalendername - auf Android
// typischerweise die Konto-Mailadresse - und Termintitel) sowie eine ganze
// Fehlerklasse: `catch (e) { debugPrint("... $e") }`.
//
// Letztere ist die subtile: `FormatException.toString()` enthaelt einen
// Ausschnitt der QUELLZEICHENKETTE. Ueber `$e` gelangen damit Nutzdaten ins
// Log, die im Format-String selbst gar nicht vorkommen - bei beschaedigten
// SharedPreferences also Alarmtitel, geplante Weckzeiten oder der
// Deaktivierungscode selbst. Deshalb darf `debugPrint` eine Ausnahme nur noch
// als `runtimeType` aufnehmen.
//
// Dieser Test ist absichtlich quelltextlesend: er verbietet den KANAL, nicht
// einen konkreten Wert. Ein Wert-basierter Test wuerde nur die heute bekannten
// Lecks fangen.

/// Ausdruecke, die niemals in einer Log-Ausgabe interpoliert werden duerfen.
/// Schluessel = Regex auf den Argumenten von debugPrint, Wert = Begruendung.
const _forbidden = <String, String>{
  r'\$\{?\s*e\s*\}?(?![a-zA-Z0-9_.])':
      r'Eine Ausnahme darf nur als ${e.runtimeType} geloggt werden - '
          'FormatException.toString() echot die Quellzeichenkette.',
  r'rawValue': 'Der gescannte QR-Rohwert ist das Deaktivierungsgeheimnis.',
  r'\.payload': 'Der Deaktivierungscode selbst.',
  r'deactivationCode\b(?!\s*==|\s*!=|\s*is\b)':
      'Der Deaktivierungscode selbst (Vergleiche auf null sind erlaubt).',
  r'eventName': 'Termintitel aus dem Geraetekalender.',
  r'\.description': 'Terminbeschreibung aus dem Geraetekalender.',
  r'calendar\.name|\.name\b(?=[^)]*\})':
      'Kalendername - auf Android regelmaessig die Konto-Mailadresse.',
};

/// Findet die Argumentliste jedes debugPrint-Aufrufs, ueber Zeilenumbrueche
/// hinweg (viele Aufrufe im Projekt sind mehrzeilig formatiert).
Iterable<({int line, String args})> _debugPrintCalls(String source) {
  final out = <({int line, String args})>[];
  const needle = 'debugPrint(';
  var index = source.indexOf(needle);
  while (index != -1) {
    var depth = 0;
    var i = index + needle.length - 1;
    final start = i + 1;
    for (; i < source.length; i++) {
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    out.add((
      line: source.substring(0, index).split('\n').length,
      args: source.substring(start, i < source.length ? i : source.length),
    ));
    index = source.indexOf(needle, i);
  }
  return out;
}

void main() {
  test('keine Log-Ausgabe in lib/ interpoliert personenbezogene oder geheime Daten',
      () {
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      for (final call in _debugPrintCalls(source)) {
        for (final entry in _forbidden.entries) {
          if (RegExp(entry.key).hasMatch(call.args)) {
            violations.add(
                '${entity.path}:${call.line}\n      ${call.args.trim()}\n      -> ${entry.value}');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Diese Log-Ausgaben koennen Nutzerdaten oder Geheimnisse '
          'preisgeben:\n\n${violations.join('\n\n')}\n',
    );
  });

  // Der einzige debugPrint, der den Release-Guard aus main.dart umgeht: er
  // sitzt in runTimezoneCheckpoint2, das per @pragma('vm:entry-point') in einem
  // EIGENEN Isolate laeuft. Dort ist main() nie gelaufen, also gilt der
  // debugPrint-Default und schreibt auch im Release nach logcat.
  test('der Hintergrund-Isolate-Pfad loggt nichts Interpoliertes', () {
    final source = File('lib/models/scheduling/replan.dart').readAsStringSync();
    final checkpoint2 = source.substring(source.indexOf('runTimezoneCheckpoint2'));

    for (final call in _debugPrintCalls(checkpoint2)) {
      // Erlaubt ist genau eine Form: der Typ einer Ausnahme. Alles andere
      // waere ein Wert, und hier landet er auch im Release im logcat.
      final interpolations =
          RegExp(r'\$\{?[^}"\x27]*\}?').allMatches(call.args).map((m) => m.group(0));
      for (final interpolation in interpolations) {
        expect(interpolation, r'${e.runtimeType}',
            reason: 'Im Hintergrund-Isolate greift der kReleaseMode-Guard aus '
                'main.dart nicht - diese Zeile landet auch im Release im '
                'logcat: ${call.args.trim()}');
      }
    }
  });
}
