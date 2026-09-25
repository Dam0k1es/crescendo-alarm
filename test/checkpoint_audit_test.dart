import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/notifications.dart';

// Regressions from the independent spec review (2026-09-11), at the
// checkpoint-trigger level. The domain layer and replan() live in
// scheduling_v2_audit_test.dart and replan_audit_test.dart respectively.

class _SilentNotifications implements Notifications {
  int scheduleCount = 0;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    scheduleCount++;
    return id ?? 1;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> cancelAllNotifications() async {}
}

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  tzdata.initializeTimeZones();

  group('FR-17: the daily lock checks "!= today", not ">= today" (T-109)',
      () {
    // FR-17, verbatim:
    //
    //   "If `lastReplanDate` != today's calendar date (device time zone):
    //    immediately, before any UI interaction, the same sequence as FR-8's
    //    ring checkpoint [...] Otherwise: no additional checkpoint."
    //
    // The code read `!midnight(last).isBefore(midnight(now))`, i.e. ">=".
    // For a `lastReplanDate` in the FUTURE this got skipped, even though
    // FR-17 requires "!=".
    //
    // The marker ends up in the future with no action by the app at all:
    // it's a device-local digit date with no clamping, and a zone change
    // across the date boundary (or a backward correction of the system
    // clock) makes the local date jump backward. Exactly then the one
    // mechanism that could still repair a stale plan fails - and precisely
    // in the three gaps FR-17 is built for (reboot, force-quit, a daily ring
    // that failed to happen), where there is no ring to repair the marker
    // as a side effect.

    test('lastReplanDate tomorrow: the foreground checkpoint runs', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _tomorrowOf(DateTime.utc(2026, 3, 10));

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => DateTime.utc(2026, 3, 10, 9, 0),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const <Meeting>[],
        notifications: _SilentNotifications(),
      );

      expect(result, isNotNull,
          reason: 'FR-17: != today -> full checkpoint');
      expect(appState.lastReplanDate, DateTime.utc(2026, 3, 10));
    });

    test('lastReplanDate today: still a no-op', () async {
      // Counter-check: FR-17's actual purpose (at most once daily) must not
      // be lost.
      final appState = await _freshAppState();
      appState.lastReplanDate = DateTime.utc(2026, 3, 10);

      var fetches = 0;
      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => DateTime.utc(2026, 3, 10, 20, 0),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async {
          fetches++;
          return const <Meeting>[];
        },
        notifications: _SilentNotifications(),
      );

      expect(result, isNull);
      expect(fetches, 0);
    });

    test('lastReplanDate yesterday: still runs', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = DateTime.utc(2026, 3, 9);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => DateTime.utc(2026, 3, 10, 9, 0),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const <Meeting>[],
        notifications: _SilentNotifications(),
      );

      expect(result, isNotNull);
    });

    test('a real date rollback: Apia (+13) to Pago Pago (-11)', () async {
      // The case that actually produces this - as real IANA zones, not as a
      // UTC fixture: on this UTC+0 VM, a `DateTime.utc` fixture cannot
      // represent a date rollback at all.
      final apia = tz.getLocation('Pacific/Apia');
      final pago = tz.getLocation('Pacific/Pago_Pago');

      final beforeFlight = tz.TZDateTime(apia, 2026, 3, 10, 8, 0);
      // The same instant, read in Pago Pago: a 24-hour offset difference,
      // i.e. Mar 9 - one calendar day BACK, even though time itself moves
      // forward.
      final afterFlight =
          tz.TZDateTime.from(beforeFlight.add(const Duration(hours: 2)), pago);

      expect(afterFlight.day, lessThan(beforeFlight.day),
          reason: 'fixture check: the local date really does jump backward');
      expect(afterFlight.isAfter(beforeFlight), isTrue,
          reason: 'fixture check: the second instant is really later');

      final appState = await _freshAppState();
      var fetches = 0;
      Future<List<Meeting>> fetch(DateTime start, DateTime end) async {
        fetches++;
        return const <Meeting>[];
      }

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => beforeFlight,
        deviceUtcOffset: beforeFlight.timeZoneOffset,
        fetchEvents: fetch,
        notifications: _SilentNotifications(),
      );
      expect(fetches, 1, reason: 'the first checkpoint runs');

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => afterFlight,
        deviceUtcOffset: afterFlight.timeZoneOffset,
        fetchEvents: fetch,
        notifications: _SilentNotifications(),
      );

      expect(result, isNotNull,
          reason: 'FR-17: the local date differs -> checkpoint');
      expect(fetches, 2,
          reason: 'and with it an uncached calendar re-read');
    });
  });
}

DateTime _tomorrowOf(DateTime day) => day.add(const Duration(days: 1));
