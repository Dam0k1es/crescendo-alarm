// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

// docs/TODO.md T-62: docs/scheduling-v2-spec.md's own FR-16 "Precondition"
// section calls it "verified from the package source, high confidence" that
// scheduling a title/body-less NotificationContent (the "background
// notification" sleepReminderContent(reminderEnabled: false) produces) still
// fires onNotificationCreatedMethod at the scheduled time - but recommends a
// real/emulated device confirmation before relying on it, since there is no
// Android emulator/device in the environment this claim was first checked
// in. This is that confirmation.
//
// Why a separate file, not a case inside app_test.dart: this needs to wait
// out a real scheduled time (via NotificationCalendar, not Alarm.set), which
// none of app_test.dart's scenarios do, and app_test.dart's own setUp/
// tearDown call Alarm.stopAll() and reset AppState - orthogonal concerns
// this test has no use for.
//
// What this does NOT prove: that the callback still fires after the OS has
// fully backgrounded and later killed the Dart engine's main isolate (FR-16's
// own wording, "including after the app has been backgrounded") - simulating
// that from inside a widget test is not practical. What it DOES prove: that
// scheduling a real, title/body-less NotificationContent through the app's
// own production code path (Notifications.scheduleNotification) actually
// causes AwesomeNotifications to invoke onNotificationCreatedMethod at all,
// on a real device - the specific mechanism FR-16's Checkpoint 2 depends on,
// and the one part of this claim that could not be checked at all without a
// device.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/utils/notifications.dart';

/// Repeatedly pumps a real, short duration until [check] returns true or
/// [timeout] elapses - the same "wait on a real, slow, external event"
/// pattern app_test.dart's own pumpUntilFound uses, since a plain
/// `Future.delayed` would starve the engine of the frames
/// AwesomeNotifications' platform channel needs to deliver the callback.
Future<bool> pumpUntilTrue(
  WidgetTester tester,
  Future<bool> Function() check, {
  Duration timeout = const Duration(seconds: 45),
  Duration step = const Duration(seconds: 1),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (await check()) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a title/body-less scheduled notification fires onNotificationCreatedMethod',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    // A UTC offset is always a multiple of 15 minutes and within +-14 hours
    // - this sentinel cannot occur naturally, so a change can only have come
    // from runTimezoneCheckpoint2 actually running.
    const sentinel = 999999;
    await prefs.setInt('lastCheckedUtcOffsetMinutes', sentinel);

    final notifications = Notifications();
    await notifications.init();
    final scheduledId = await notifications.scheduleNotification(
      title: null,
      body: null,
      scheduledDate: DateTime.now().add(const Duration(seconds: 15)),
    );
    expect(scheduledId, isNot(-1),
        reason: 'scheduling itself must succeed, or nothing below can prove '
            'anything about the callback');

    final fired = await pumpUntilTrue(tester, () async {
      // onNotificationCreatedMethod runs in its own background isolate with
      // its own SharedPreferences handle - re-fetch a fresh instance each
      // check rather than trusting this process's cached one, the same
      // caution the rest of this app takes around the same isolate boundary
      // (docs/TODO.md T-89).
      SharedPreferences.resetStatic();
      final freshPrefs = await SharedPreferences.getInstance();
      return freshPrefs.getInt('lastCheckedUtcOffsetMinutes') != sentinel;
    });

    expect(fired, isTrue,
        reason: 'runTimezoneCheckpoint2 (called from '
            'onNotificationCreatedMethod) unconditionally rewrites this key - '
            'if it never changed, the silent notification never fired the '
            'callback at all');
  });
}
