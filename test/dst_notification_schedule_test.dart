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

// docs/TODO.md T-202 (c), TZ-8: the bedtime reminder is scheduled through
// awesome_notifications' `NotificationCalendar.fromDate`, which does not
// carry an instant at all - it copies the DateTime's year/month/day/hour/
// minute/second fields plus a zone NAME (the device zone for a local value,
// "UTC" for a UTC-tagged one, awesome_notifications 0.12.1
// lib/src/models/notification_calendar.dart:84-98). The native side
// (AndroidAwnCore 0.12.1, `NotificationCalendarModel.getNextValidDate`)
// turns those fields into a cron expression and evaluates it with
// `CronExpression.setTimeZone(timeZone)` - i.e. it re-resolves a wall-clock
// reading. A local reading inside the repeated fall-back hour names two
// instants; in UTC every reading names exactly one.
//
// So the schedule is built from the UTC fields with the "UTC" zone:
// `notificationCalendarAt` is the one place that happens, and this test
// reconstructs the instant from exactly what the plugin is handed.

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/utils.dart';

import 'support/local_zone_transitions.dart';

/// The instant the native side will compute from the calendar's fields,
/// valid only for the UTC zone name (the only one without ambiguity).
int _instantFromCalendarFields(dynamic calendar) => DateTime.utc(
      calendar.year as int,
      calendar.month as int,
      calendar.day as int,
      calendar.hour as int,
      calendar.minute as int,
      calendar.second as int,
    ).millisecondsSinceEpoch;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final overlaps = localTransitions().where((t) => t.isOverlap).toList();

  test('a reminder in the second pass of a repeated hour is handed over as '
      'UTC fields with the UTC zone', () {
    final berlinSecond = tz.TZDateTime.from(
        DateTime.utc(2026, 10, 25, 1, 30), tz.getLocation('Europe/Berlin'));
    final lordHoweSecond = tz.TZDateTime.from(
        DateTime.utc(2026, 4, 4, 15, 15), tz.getLocation('Australia/Lord_Howe'));
    final instants = [
      berlinSecond.millisecondsSinceEpoch,
      lordHoweSecond.millisecondsSinceEpoch,
      for (final t in overlaps) t.secondPassMs(t.wallMiddleMs),
    ];
    for (final ms in instants) {
      // As scheduleSleepReminder passes it: the local whole minute.
      final scheduled =
          alarmPlatformTime(DateTime.fromMillisecondsSinceEpoch(ms));
      final calendar = notificationCalendarAt(scheduled);
      expect(calendar.timeZone, 'UTC');
      // The plugin's one second of lead (kept from before) and nothing else.
      expect(_instantFromCalendarFields(calendar), ms + 1000,
          reason: 'scheduled for $scheduled (${scheduled.timeZoneOffset})');
      expect(calendar.repeats, isFalse);
      expect(calendar.preciseAlarm, isTrue);
    }
  });

  test('counter-test: an ordinary local time names the same instant', () {
    final scheduled = DateTime(2026, 7, 10, 22, 30);
    final calendar = notificationCalendarAt(scheduled);
    expect(calendar.timeZone, 'UTC');
    expect(_instantFromCalendarFields(calendar),
        scheduled.millisecondsSinceEpoch + 1000);
  });
}
