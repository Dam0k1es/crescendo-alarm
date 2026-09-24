import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

// docs/TODO.md T-89: the event logger should deliver diagnostically useful
// feedback from real usage WITHOUT collecting personal data.
//
// The load-bearing design decision is that this freedom is enforced
// *structurally*, not disciplinarily: the recording API takes not a single
// String. That leaves no channel through which an appointment title, a
// calendar name, an exception message, or the QR deactivation code could
// enter - what cannot be represented cannot leak.
//
// This test checks exactly that property against the source, because it
// can't be derived from values: a value-based test would only catch the
// leaks known today, not the next newly added parameter.

/// The logger's source. Deliberately read fresh per test and **not**
/// prepared with `expect` in `setUpAll`: an assertion in `setUpAll`
/// leaves the test harness hanging instead of failing cleanly (this
/// really happened - the run sat in `(setUpAll)` for minutes).
String _source() => File('lib/utils/diag/diag_log.dart').readAsStringSync();

/// The public facade: everything from the marker onward. Above it sit the
/// enum definitions and the private reduction functions, where strings
/// (doc comments, prefs keys) are legitimately present.
String _publicApi() {
  const marker = '// == PUBLIC RECORDING API ==';
  final source = _source();
  final index = source.indexOf(marker);
  if (index < 0) {
    fail('The marker "$marker" delimits the public facade - '
        'without it this test cannot check what it is meant to check.');
  }
  return source.substring(index);
}

void main() {

  group('structural PII-freedom', () {
    test('no public method takes a String', () {
      // Collects the facade's parameter lists and looks for String types.
      // Matches both static and instance methods, and generic return types
      // (e.g. `Future<void>`) - not just `static void name(...)`, which
      // would silently miss any method that isn't shaped exactly like
      // today's. The return-type token must start with a letter/underscore
      // so it can't accidentally match the ">" of a preceding "=>" spanning
      // onto the next line.
      final offenders = <String>[];
      for (final match in RegExp(
              r'^\s*(?:static\s+)?[A-Za-z_]\w*(?:<[^>]*>)?\??\s+(\w+)\s*\(([^)]*)\)',
              multiLine: true)
          .allMatches(_publicApi())) {
        final name = match.group(1)!;
        final params = match.group(2)!;
        if (RegExp(r'\bString\b').hasMatch(params)) {
          offenders.add('$name($params)');
        }
      }
      expect(offenders, isEmpty,
          reason: 'A String parameter is a PII channel. Use an enum, '
              'a counter, or a Type instead:\n${offenders.join('\n')}');
    });

    test('the sink holds no strings, only numbers', () {
      // DiagRecord.encode() is the only place where a record leaves the
      // in-memory structure. It must produce List<int>.
      expect(_source(), contains('List<int> encode()'),
          reason: 'A record is encoded as a plain list of numbers - that '
              'way no free text can land in SharedPreferences.');
    });

    test('no debugPrint and no print in the logger itself', () {
      // Otherwise the PII-free logger would itself be a log leak, and in
      // the background isolate main.dart's kReleaseMode guard would not
      // apply.
      expect(RegExp(r'(?<![A-Za-z0-9_])debugPrint\(').hasMatch(_source()), isFalse);
      expect(RegExp(r'(?<![A-Za-z0-9_.])print\(').hasMatch(_source()), isFalse);
    });

    test('no clock read in the logger', () {
      // Ordering comes from a counter, durations from Stopwatch. A
      // timestamp per event would, together with the wake events, be a
      // sleep pattern - and therefore identifying without any name.
      expect(_source().contains('DateTime.now()'), isFalse,
          reason: 'No DateTime.now() in the logger - ordering via bootSeq/'
              'seq, coarse timing via Stopwatch buckets.');
      expect(_source().contains('DateTime.timestamp()'), isFalse);
    });

    test('int parameters are only counts and relative days', () {
      // Anything that stems from a clock enters the log exclusively as a
      // bucket enum. An int named "...Minutes"/"...Ms"/"...Epoch" would be
      // a raw value and therefore a path back to the wall clock.
        // The ONE allowed exception, and it is named here explicitly so
        // that it stays a decision, not an accident (docs/TODO.md T-135):
        // `Diag.dayPlanned` carries a day's planned wake time and earliest
        // appointment as a minute of the local day. Without these two
        // numbers the log cannot reconstruct WHY a given day got that wake
        // time - that is exactly what T-132's diagnosis hinged on, and it
        // could only be done via screenshots and hand arithmetic.
        //
        // The event only writes when clock-time logging is explicitly
        // switched on (default off; the test for that lives in
        // diag_log_test.dart). The constructive assertion therefore still
        // holds for the default setting - just only for that one.
        const allowed = {
          'plannedMinuteOfDay',
          'earliestEventMinuteOfDay',
          'preferredWakeUpMinuteOfDay',
          // T-163 (maintainer request): one calendar event's start/end
          // within the planning window, minute-of-day only - same opt-in
          // switch as the three above, same reasoning. Deliberately no
          // other property of the event: no title, description, attendee,
          // location, or which calendar it came from. `Diag.dayEventTime`'s
          // own doc comment has the full rationale.
          'startMinuteOfDay',
          'endMinuteOfDay',
          // Durations, not clock times (T-140): "90-minute cap" or
          // "30-minute lead time" reveal nothing about sleep - they are
          // configuration values, without which a logged plan can't be
          // recomputed. They therefore are ALWAYS in the log, not only
          // behind the clock-time switch. The rule remains: no clock
          // value without a switch.
          'maxDailyDeltaMinutes',
          'wakeUpMinutes',
          'getReadyMinutes',
        };

        final offenders = <String>[];
        // Matches `int`, `int?` (nullable) and `List<int>`/`Set<int>`
        // (collections) - not only a bare `required int name`, which a
        // future clock-shaped parameter could otherwise slip past in
        // either of those shapes.
        for (final match in RegExp(r'required\s+(?:int\??|List<int>|Set<int>)\s+(\w+)')
            .allMatches(_publicApi())) {
          final name = match.group(1)!;
          if (allowed.contains(name)) continue;
          // "MinuteOfDay"/"HourOfDay" explicitly included as well:
          // otherwise a "...OfDay" suffix is enough to slip past this
          // rule - as very nearly happened with the two exceptions above.
          if (RegExp(r'(Minutes|Ms|Millis|Epoch|Time|Date|Hour|Clock|MinuteOfDay|HourOfDay)$')
              .hasMatch(name)) {
            offenders.add(name);
          }
        }
        expect(offenders, isEmpty,
            reason: 'These int parameters carry a clock value. Reduce them '
                'to a bucket enum first - or list them, with a reason '
                'and behind a switch, in `allowed` above:\n'
                '${offenders.join(', ')}');
    });
  });

  group('encoding and bounds', () {
    test('event and field codes are stable and unique', () {
      // A Dart enum's index shifts when reordered; but an exported log
      // must still be readable by a different app version. Hence explicit
      // codes - and they must be unique.
      final eventCodes = DiagEvent.values.map((e) => e.code).toList();
      expect(eventCodes.toSet().length, eventCodes.length,
          reason: 'duplicate DiagEvent code');
      final fieldCodes = DiagField.values.map((f) => f.code).toList();
      expect(fieldCodes.toSet().length, fieldCodes.length,
          reason: 'duplicate DiagField code');
    });

    test('the ring buffer is bounded from above', () {
      // Lesson from T-82: unbounded growth is doubly harmful here -
      // it eats memory AND turns the log into a long-term profile.
      expect(Diag.capacity, lessThanOrEqualTo(1024));
      expect(Diag.capacity, greaterThanOrEqualTo(128));
    });
  });
}
