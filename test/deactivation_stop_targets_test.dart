import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_stop.dart';

// An independent review of the scanner migration found that a successful scan
// could cancel EVERY armed alarm while nothing was ringing at all.
//
// The path: the import screen (`PageImportQr`) builds the scanner without an
// `alarmId`. The first decode imports the code and leaves the camera running;
// about a second later the same code decodes again, now validates, and the
// "which alarm is ringing? none given, so stop them all" fallback fires. The
// planned week is repaired by the next checkpoint, but manual alarms are not -
// nothing re-arms those. They stay listed and switched on while being gone from
// the platform, which is a silent oversleep: the worst outcome this app has.
//
// The decision therefore lives in a pure function, so it can be pinned here
// rather than only being reachable through a camera.

void main() {
  group('deactivationStopTargets', () {
    test('a known ringing alarm is the only target', () {
      // docs/TODO.md T-74e: stop exactly the alarm that rang, not every saved
      // one - stopping the others cancelled them at the platform while
      // AppState still believed they existed.
      expect(
        deactivationStopTargets(
          ringingAlarmId: 42,
          platformAlarmIds: const [1, 2, 42, 99],
          anythingRinging: true,
        ),
        const [42],
      );
    });

    test('nothing ringing means nothing is stopped', () {
      // The finding above. Scanning a code out of curiosity, or re-scanning it
      // on the import screen, must not disarm the week.
      expect(
        deactivationStopTargets(
          ringingAlarmId: null,
          platformAlarmIds: const [1, 2, 3],
          anythingRinging: false,
        ),
        isEmpty,
      );
    });

    test('something rings but nobody said which: stop everything', () {
      // The fallback stays, because the alternative is worse: an alarm that
      // rings on and cannot be switched off by the code the user just scanned.
      // It is now reachable only when something really is ringing.
      expect(
        deactivationStopTargets(
          ringingAlarmId: null,
          platformAlarmIds: const [1, 2, 3],
          anythingRinging: true,
        ),
        const [1, 2, 3],
      );
    });

    test('a known ringing alarm is stopped even if the platform list is stale',
        () {
      // Counter-test: the id the handler passed wins over the list. A platform
      // query that comes back empty or outdated must not leave the ringing
      // alarm running.
      expect(
        deactivationStopTargets(
          ringingAlarmId: 7,
          platformAlarmIds: const [],
          anythingRinging: true,
        ),
        const [7],
      );
    });
  });
}
