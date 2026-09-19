// Copyright (C) 2026 Dam0k1es
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

// A prelude for scripts/verify-notification-survival.sh (docs/TODO.md T-155):
// schedules a single, silent, title/body-less notification a few hours out
// through the app's own Notifications.scheduleNotification - the exact
// production call scheduleSleepReminder eventually makes - and leaves it
// STANDING, the same shape as integration_test/arm_alarm_test.dart does for
// the alarm-survival leg (T-93).
//
// Why a separate file, not integration_test/silent_notification_test.dart
// (T-62): that file schedules 15 seconds out and waits IN-PROCESS for the
// callback to fire - useful for proving the callback mechanism works at
// all, useless for a reboot test, which needs the schedule to still be
// hours in the future when the device comes back up, and needs the test
// process itself to exit immediately rather than block waiting for
// anything.
//
// Several hours, not minutes: the schedule must not have a "next valid
// date" that has already passed by the time a human reads dumpsys output,
// reboots the device, and it finishes booting - unlike arm_alarm_test.dart's
// two hours (a `ManualAlarm`'s own stale-alarm handling is more forgiving),
// this is specifically testing whether a ONE-SHOT notification schedule
// still has `hasNextValidDate() == true` at measurement time, so cutting
// it close would confound "did it survive" with "did it just expire
// naturally in the meantime".

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/utils/notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'schedules a silent notification several hours out and leaves it standing',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final notifications = Notifications();
    await notifications.init();

    final target = DateTime.now().add(const Duration(hours: 6));
    final id = await notifications.scheduleNotification(
      title: null,
      body: null,
      scheduledDate: target,
    );
    expect(id, isNot(-1),
        reason: 'without a successfully scheduled notification, the reboot '
            'check is meaningless');

    // Deliberately NO cancelNotification here - it must survive the reboot.
  });
}
