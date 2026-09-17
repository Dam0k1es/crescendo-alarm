import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-89: PII-freedom of the log output is checked structurally,
// not by discipline. An independent audit found five critical leaks
// (the QR deactivation code in three places, the calendar name - on
// Android typically the account's email address - and appointment titles)
// as well as a whole bug class: `catch (e) { debugPrint("... $e") }`.
//
// The latter is the subtle one: `FormatException.toString()` contains a
// slice of the SOURCE STRING. Via `$e`, user data therefore enters the
// log that doesn't appear in the format string itself at all - with
// corrupted SharedPreferences that means alarm titles, planned wake
// times, or the deactivation code itself. That's why `debugPrint` may
// only ever take an exception as a `runtimeType` from now on.
//
// This test is deliberately source-reading: it forbids the CHANNEL, not
// a specific value. A value-based test would only catch the leaks known
// today.

/// Expressions that must never be interpolated into a log line.
/// Key = regex on debugPrint's arguments, value = the reason.
const _forbidden = <String, String>{
  r'\$\{?\s*e\s*\}?(?![a-zA-Z0-9_.])':
      r'An exception may only be logged as ${e.runtimeType} - '
          'FormatException.toString() echoes the source string.',
  r'rawValue': 'The scanned QR raw value is the deactivation secret.',
  r'\.payload': 'The deactivation code itself.',
  r'deactivationCode\b(?!\s*==|\s*!=|\s*is\b)':
      'The deactivation code itself (comparisons against null are allowed).',
  r'eventName': 'Appointment title from the device calendar.',
  r'\.description': 'Appointment description from the device calendar.',
  r'calendar\.name|\.name\b(?=[^)]*\})':
      'Calendar name - on Android regularly the account email address.',
};

/// Finds the argument list of every debugPrint call, across line breaks
/// (many calls in the project are formatted across multiple lines).
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
  test('no log output in lib/ interpolates personal or secret data',
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
      reason: 'These log lines can expose user data or secrets:\n\n'
          '${violations.join('\n\n')}\n',
    );
  });

  // The one debugPrint that bypasses main.dart's release guard: it sits
  // in runTimezoneCheckpoint2, which runs in its OWN isolate via
  // @pragma('vm:entry-point'). main() never ran there, so debugPrint's
  // default applies and it writes to logcat even in release.
  test('the background isolate path logs nothing interpolated', () {
    final source = File('lib/models/scheduling/replan.dart').readAsStringSync();
    final checkpoint2 = source.substring(source.indexOf('runTimezoneCheckpoint2'));

    for (final call in _debugPrintCalls(checkpoint2)) {
      // Exactly one form is allowed: an exception's type. Anything else
      // would be a value, and here it lands in logcat even in release.
      final interpolations =
          RegExp(r'\$\{?[^}"\x27]*\}?').allMatches(call.args).map((m) => m.group(0));
      for (final interpolation in interpolations) {
        expect(interpolation, r'${e.runtimeType}',
            reason: 'In the background isolate main.dart\'s kReleaseMode '
                'guard does not apply - this line lands in logcat even in '
                'release: ${call.args.trim()}');
      }
    }
  });
}
