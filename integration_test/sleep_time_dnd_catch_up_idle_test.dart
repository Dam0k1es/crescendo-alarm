// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

// docs/TODO.md T-200 (maintainer request, 2026-09-27): on the maintainer's
// Android 16 phone the sleep-time Do Not Disturb catch-up - designed for
// ~2 minutes after the push (T-110) - came on only after roughly 10-15
// minutes, while `sleep_time_dnd_test.dart` measures it at ~2 minutes on the
// CI emulator. That leg runs under ideal conditions the phone does not have:
// run_e2e_tests.sh grants SCHEDULE_EXACT_ALARM explicitly, the screen stays
// on, the device never dozes, and the timing is read from inside the app.
//
// This scenario reproduces the phone's conditions instead. The script
// (`.github/scripts/run_e2e_tests.sh`, "catch-up under idle" leg) resets
// SCHEDULE_EXACT_ALARM to the platform default before this runs, and - once
// this test prints its CATCHUP_PUSHED marker - records the pending alarm
// entry (`dumpsys alarm`: exact or windowed?), turns the screen off, forces
// Doze, and measures from OUTSIDE the app, by polling the platform's own zen
// mode, how long the catch-up takes. This test only pushes the window and
// then keeps the app process (and with it the instrumentation) alive long
// enough for that measurement; `flutter test` uninstalls the app when it
// ends, and Android drops a package's AlarmManager entries with it (T-131).
//
// NON-GATING evidence, like the legs around it: the question is "how late,
// and why", which a pass/fail alone would not answer.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart';

const _filterAlarms = 4;

/// Emits a marker the script can see WHILE the test runs. `print` inside
/// `testWidgets` is captured by the test zone and only reaches `flutter
/// test`'s output (and logcat) when the test ends - the second run of this
/// leg (36333862160) therefore never saw CATCHUP_PUSHED in logcat at all.
/// `stdout` bypasses that zone; on Android it goes straight to logcat.
void _mark(String line) {
  stdout.writeln(line);
  // ignore: avoid_print
  print(line);
}

/// How long the app stays alive for the script's measurement. The phone
/// report was ~10-15 minutes; 16 leaves room to see a delay of that size
/// rather than cutting it off.
const _observation = Duration(minutes: 16);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catch-up activation time under Doze with default exact-alarm '
      'permission (evidence)', (tester) async {
    // The script re-applies the Do Not Disturb grant and the exact-alarm
    // reset in a loop, because `flutter test` reinstalls the package; give
    // that loop a few rounds before arming anything.
    await tester.pump(const Duration(seconds: 10));

    final pushedAt = DateTime.now();
    final report = await pushSleepTimeWindow(
      enabled: true,
      window: (
        start: pushedAt.subtract(const Duration(seconds: 1)),
        end: pushedAt.add(_observation + const Duration(minutes: 4)),
      ),
    );
    _mark('CATCHUP_PUSHED decision=${report.decision.name} '
        'accessMissing=${report.accessMissing}');
    expect(report.decision, SleepTimeDndDecision.catchUp,
        reason: 'without a catch-up decision there is nothing to measure');

    // Keep the process alive; record, as a cross-check, when the app itself
    // first sees the filter change (the script's outside measurement is the
    // authoritative one - this loop may itself be throttled under Doze).
    Duration? seenAfter;
    final deadline = pushedAt.add(_observation);
    while (DateTime.now().isBefore(deadline)) {
      if (seenAfter == null &&
          await readCurrentInterruptionFilter() == _filterAlarms) {
        seenAfter = DateTime.now().difference(pushedAt);
        _mark('CATCHUP_SEEN_IN_APP afterSeconds=${seenAfter.inSeconds}');
        // Hold on a little so the script's outside poll (every 5 s) sees it
        // too - `flutter test` uninstalls the app when this ends, which
        // removes the app's Do Not Disturb mode with it - then stop: no
        // reason to hold the job for the rest of the observation.
        await tester.pump(const Duration(seconds: 30));
        break;
      }
      await tester.pump(const Duration(seconds: 5));
    }

    await pushSleepTimeWindow(enabled: false, window: null);
    expect(seenAfter, isNotNull,
        reason: 'the catch-up never activated within $_observation');
    expect(seenAfter!, lessThanOrEqualTo(const Duration(minutes: 3)),
        reason: 'designed for ~2 minutes after the push (T-110); the '
            "script's zen_mode timeline in the evidence shows the real delay");
  }, timeout: const Timeout(Duration(minutes: 20)));
}
