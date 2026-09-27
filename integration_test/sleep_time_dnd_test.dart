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

// docs/TODO.md T-198: the sleep-time Do Not Disturb trigger against the REAL
// platform - real MethodChannel, real AlarmManager alarms, the real
// SleepTimeDndReceiver, and the real NotificationManager interruption filter
// read back through `getCurrentInterruptionFilter()`. No fakes anywhere.
//
// This is the check T-197 said was missing: the removed T-184 feature passed
// six rounds of unit tests against injected `getCurrentFilter`/`setFilter`
// fakes and still (1) switched Do Not Disturb on immediately and (2) never
// switched it off after the ring, on a real phone. Here the two symptoms are
// asserted on the platform's own state:
//
// 1. pushing a window whose start lies ahead changes NOTHING at that moment;
// 2. Do Not Disturb comes on at the window's start and goes off at its end,
//    each from the native alarm, with no Dart call in between.
//
// NON-GATING (like silent_notification_test.dart): run by
// .github/scripts/run_e2e_tests.sh with `|| true`. It needs Android's "Do Not
// Disturb access", which the script grants with
// `adb shell cmd notification allow_dnd` while this runs.
//
// What this does NOT cover, stated plainly: the CI emulator is API 34, i.e.
// the legacy global-Do-Not-Disturb model, not Android 15's per-app implicit
// rule the maintainer's phone uses (SleepTimeDndPolicy's API >= 35 branch);
// and the app process stays alive throughout, so "the end fires with the app
// process dead" rests on the receiver path being engine-free by
// construction, not on this run.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart';

const _filterAll = 1;
const _filterAlarms = 4;

/// Pumps (real time passes in the live integration binding) until [check]
/// holds or [timeout] elapses; returns the moment it first held, or null.
Future<DateTime?> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() check, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (await check()) return DateTime.now();
    await tester.pump(step);
  }
  return await check() ? DateTime.now() : null;
}

Future<bool> _filterIs(int expected) async =>
    await readCurrentInterruptionFilter() == expected;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'sleep-time Do Not Disturb follows its window on the real platform',
      (tester) async {
    final granted = await _pumpUntil(tester, readDndAccessGranted,
        timeout: const Duration(seconds: 120));
    expect(granted, isNotNull,
        reason: 'Do Not Disturb access was never granted - the runner script '
            'grants it with `cmd notification allow_dnd`; without it nothing '
            'below can prove anything');

    // A clean slate: feature off, Do Not Disturb off.
    await pushSleepTimeWindow(enabled: false, window: null);
    expect(await _pumpUntil(tester, () => _filterIs(_filterAll),
            timeout: const Duration(seconds: 10)),
        isNotNull,
        reason: 'precondition: Do Not Disturb must be off before the test');

    // --- Symptom 1: the next alarm is days away. -------------------------
    final daysAway = DateTime.now().add(const Duration(days: 3));
    var report = await pushSleepTimeWindow(
      enabled: true,
      window: (start: daysAway, end: daysAway.add(const Duration(hours: 8))),
    );
    expect(report.decision, SleepTimeDndDecision.scheduled);
    await tester.pump(const Duration(seconds: 5));
    expect(await readCurrentInterruptionFilter(), _filterAll,
        reason: 'T-197 symptom 1: switching on while the alarm is days away '
            'must not activate Do Not Disturb');

    // --- A real window: start in 20 s, end in 50 s. ----------------------
    final pushedAt = DateTime.now();
    final start = pushedAt.add(const Duration(seconds: 20));
    final end = pushedAt.add(const Duration(seconds: 50));
    report = await pushSleepTimeWindow(
        enabled: true, window: (start: start, end: end));
    expect(report.decision, SleepTimeDndDecision.scheduled);
    expect(await readCurrentInterruptionFilter(), _filterAll,
        reason: 'symptom 1 again: arming the window must not activate it');

    final cameOn = await _pumpUntil(tester, () => _filterIs(_filterAlarms),
        timeout: const Duration(seconds: 60));
    expect(cameOn, isNotNull,
        reason: 'the start alarm never switched Do Not Disturb on');
    expect(cameOn!.isBefore(start.subtract(const Duration(seconds: 1))),
        isFalse,
        reason: 'Do Not Disturb came on at $cameOn, before the window start '
            '$start');

    final wentOff = await _pumpUntil(tester, () => _filterIs(_filterAll),
        timeout: const Duration(seconds: 60));
    expect(wentOff, isNotNull,
        reason: 'T-197 symptom 2: the end alarm never switched Do Not '
            'Disturb off again');
    expect(wentOff!.isBefore(end.subtract(const Duration(seconds: 1))),
        isFalse,
        reason: 'Do Not Disturb went off at $wentOff, before the window end '
            '$end');

    // --- Past start: inside sleep time already (T-110's catch-up). -------
    final catchUpPushedAt = DateTime.now();
    report = await pushSleepTimeWindow(
      enabled: true,
      window: (
        start: catchUpPushedAt.subtract(const Duration(hours: 1)),
        end: catchUpPushedAt.add(const Duration(minutes: 4)),
      ),
    );
    expect(report.decision, SleepTimeDndDecision.catchUp);
    expect(await readCurrentInterruptionFilter(), _filterAll,
        reason: 'a start already passed is caught up two minutes later, not '
            'at the moment of the push');
    final caughtUp = await _pumpUntil(tester, () => _filterIs(_filterAlarms),
        timeout: const Duration(minutes: 3));
    expect(caughtUp, isNotNull, reason: 'the catch-up never activated');
    expect(caughtUp!.difference(catchUpPushedAt),
        greaterThan(const Duration(seconds: 100)));

    // --- R6: switching the feature off leaves Do Not Disturb at once. ----
    report = await pushSleepTimeWindow(enabled: false, window: null);
    expect(report.decision, SleepTimeDndDecision.disabled);
    expect(await _pumpUntil(tester, () => _filterIs(_filterAll),
            timeout: const Duration(seconds: 10)),
        isNotNull,
        reason: 'switching the feature off must leave Do Not Disturb');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
