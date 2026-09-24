import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-161 (independent security-researcher review, T-17): the
// android:permission WRITE_CALENDAR remains declared in
// android/app/src/main/AndroidManifest.xml even though this app only ever
// *reads* the calendar. It was investigated and deliberately left, not
// forgotten: permission_handler's Android implementation has no "calendar,
// read-only" request - Permission.calendarFullAccess (the only option that
// yields READ_CALENDAR, used by lib/utils/permissions.dart) asks for
// WRITE_CALENDAR in the same runtime dialog, so declaring only
// READ_CALENDAR in the manifest would leave that runtime request asking
// for a permission the manifest no longer grants.
//
// Accepting the permission is only defensible for as long as the CODE
// never actually exercises it - a manifest entry with no matching runtime
// behaviour is a stated, checkable claim, not just a belief. This guards
// that claim structurally: every `device_calendar` API that can mutate a
// calendar (createOrUpdateEvent, deleteEvent, deleteEventInstance,
// createCalendar, deleteCalendar - the package's full write surface, see
// ~/.pub-cache/hosted/pub.dev/device_calendar-*/lib/src/device_calendar.dart)
// must never be CALLED anywhere in lib/. Same "forbid the channel, not the
// symptom" reasoning as test/no_proprietary_dependencies_test.dart and
// test/diag_log_api_test.dart - a value-based/manual check would only ever
// catch a write path already known about.

const _writeMethods = <String>[
  'createOrUpdateEvent',
  'deleteEventInstance',
  'deleteEvent',
  'createCalendar',
  'deleteCalendar',
];

/// Strips '//' line comments so a call mentioned only in an explanatory
/// comment - or intentionally disabled, as `createOrUpdateEvent` currently
/// is in `calendar.dart` - does not fail this test; only a live call must.
String _stripLineComments(String source) {
  return source
      .split('\n')
      .map((line) {
        final index = line.indexOf('//');
        return index >= 0 ? line.substring(0, index) : line;
      })
      .join('\n');
}

Iterable<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  group('the app never writes to the device calendar (T-17/T-161)', () {
    test('no device_calendar write method is called anywhere in lib/', () {
      final offenders = <String>[];
      for (final file in _libDartFiles()) {
        final source = _stripLineComments(file.readAsStringSync());
        for (final method in _writeMethods) {
          if (RegExp('\\.$method\\s*\\(').hasMatch(source)) {
            offenders.add('${file.path} calls $method(...)');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'WRITE_CALENDAR is accepted in the manifest ONLY because '
              'nothing in lib/ ever exercises it (docs/TODO.md T-161) - a '
              'live call to any of these changes that risk assessment and '
              'must not land silently:\n${offenders.join('\n')}');
    });

    test('the guard would actually catch a real call', () {
      // Counter-test: prove the comment-stripping + regex combination
      // still sees a real call, not just that lib/ happens to have zero
      // matches because the check itself quietly broke.
      const liveFixture = '''
void _example() async {
  await _deviceCalendarPlugin.createOrUpdateEvent(event);
}
''';
      final stripped = _stripLineComments(liveFixture);
      expect(stripped, contains('createOrUpdateEvent'));
      expect(RegExp(r'\.createOrUpdateEvent\s*\(').hasMatch(stripped), isTrue);

      // And prove the comment-stripping half actually works: the real,
      // currently-disabled call in calendar.dart's own shape must NOT be
      // found by the same check the first test above runs.
      const commentedFixture =
          '//       await _deviceCalendarPlugin.createOrUpdateEvent(event);';
      expect(
          RegExp(r'\.createOrUpdateEvent\s*\(')
              .hasMatch(_stripLineComments(commentedFixture)),
          isFalse);
    });
  });
}
