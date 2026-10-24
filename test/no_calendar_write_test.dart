import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-161, T-244: this app only ever *reads* the calendar, yet
// WRITE_CALENDAR stays declared in android/app/src/main/AndroidManifest.xml.
// It was investigated twice and deliberately left: permission_handler's
// Android implementation has no "calendar, read-only" request -
// Permission.calendarFullAccess (the only way to get READ_CALENDAR, used by
// lib/utils/permissions.dart) answers "denied" to both status and request
// unless WRITE_CALENDAR is declared next to READ_CALENDAR
// (permission_handler_android 13.0.1, PermissionManager
// .isValidManifestForCalendarFullAccess). The move to `device_calendar_plus`
// (T-244) did not change that: the plugin itself reads with READ alone, but
// nothing could obtain the grant without the declaration.
//
// Declaring a permission is only defensible for as long as the CODE never
// exercises it, so this guards that structurally: no plugin API that can
// mutate a calendar - or that asks the plugin to request permissions itself -
// may be CALLED anywhere in lib/. Same "forbid the channel, not the symptom"
// reasoning as test/no_proprietary_dependencies_test.dart and
// test/diag_log_api_test.dart.

const _writeMethods = <String>[
  'createEvent',
  'updateEvent',
  'updateRecurring',
  'deleteEvent',
  'deleteRecurring',
  'createCalendar',
  'updateCalendar',
  'deleteCalendar',
  'showCreateEventModal',
];

/// Strips '//' line comments so a call mentioned only in an explanatory
/// comment - or intentionally disabled, as `createEvent` currently
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
    test('no calendar write method is called anywhere in lib/', () {
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
          reason: 'WRITE_CALENDAR is declared ONLY because permission_handler '
              'needs it to request a read (docs/TODO.md T-161, T-244) - a '
              'live call to any of these changes that risk assessment and '
              'must not land silently:\n${offenders.join('\n')}');
    });

    test('the plugin never requests permissions itself', () {
      // Its full-access request needs WRITE_CALENDAR declared; the request
      // goes through permission_handler (lib/utils/permissions.dart), which
      // asks for exactly what the manifest declares. `autoPermissions` would
      // make every read prompt through the plugin instead.
      final offenders = <String>[];
      for (final file in _libDartFiles()) {
        final source = _stripLineComments(file.readAsStringSync());
        if (RegExp(r'DeviceCalendar(\.instance|\(\))\s*\.requestPermissions')
                .hasMatch(source) ||
            source.contains('autoPermissions')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('the manifest declares both calendar permissions (T-244)', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final withoutComments =
          manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      for (final p in ['READ_CALENDAR', 'WRITE_CALENDAR']) {
        expect(withoutComments, contains('android.permission.$p'),
            reason: 'permission_handler_android denies the calendar status '
                'and request unless both are declared; without $p a fresh '
                'install can never be granted a calendar read');
      }
    });

    test('the guard would actually catch a real call', () {
      // Counter-test: prove the comment-stripping + regex combination
      // still sees a real call, not just that lib/ happens to have zero
      // matches because the check itself quietly broke.
      const liveFixture = '''
void _example() async {
  await DeviceCalendar.instance.createEvent(event);
}
''';
      final stripped = _stripLineComments(liveFixture);
      expect(stripped, contains('createEvent'));
      expect(RegExp(r'\.createEvent\s*\(').hasMatch(stripped), isTrue);

      // And prove the comment-stripping half actually works: the real,
      // currently-disabled call in calendar.dart's own shape must NOT be
      // found by the same check the first test above runs.
      const commentedFixture =
          '//       await DeviceCalendar.instance.createEvent(event);';
      expect(
          RegExp(r'\.createEvent\s*\(')
              .hasMatch(_stripLineComments(commentedFixture)),
          isFalse);
    });
  });
}
