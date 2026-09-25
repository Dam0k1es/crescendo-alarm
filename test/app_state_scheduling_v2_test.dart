import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart' show DayOfWeek;

// Phase 0, step 2 (docs/scheduling-v2-spec.md, "Implementation order"):
// persistence round-trip for the four new scheduling-v2 fields (FR-3),
// following the same pattern as the existing AppState fields (int ->
// setInt/getInt, string-encoded for everything else). pendingDayValues is
// additionally read back directly via a fresh SharedPreferences instance
// (not via AppState) - that simulates exactly the access the background
// isolate from FR-16 will need later (see Architecture, "real wiring" finding 1).

void main() {
  group('scheduling-v2 AppState fields (FR-3) - persistence round-trip', () {
    test('gapDayCounter (FR-9)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      first.gapDayCounter = 5;

      final second = AppState();
      await second.initialized;
      expect(second.gapDayCounter, 5);
    });

    test('lastCheckedUtcOffset (FR-16)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      first.lastCheckedUtcOffset = const Duration(hours: 9);

      final second = AppState();
      await second.initialized;
      expect(second.lastCheckedUtcOffset, const Duration(hours: 9));
    });

    test('lastReplanDate (FR-8/FR-17)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.lastReplanDate, isNull); // before the very first replan

      final today = DateTime.utc(2026, 1, 15);
      first.lastReplanDate = today;

      final second = AppState();
      await second.initialized;
      expect(second.lastReplanDate, today);
    });

    test('pendingDayValues (FR-11) - readable via AppState and directly via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      final values = <String, int?>{
        '2026-01-16': DateTime.utc(2026, 1, 16, 7, 0).millisecondsSinceEpoch,
        '2026-01-17': null, // no alarm planned (e.g. cold start, FR-10)
      };
      first.pendingDayValues = values;

      // Via a new AppState instance (simulates an app restart):
      final second = AppState();
      await second.initialized;
      expect(second.pendingDayValues, values);

      // Directly via SharedPreferences, without AppState - exactly the
      // access the background isolate from FR-16 checkpoint 2 needs:
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pendingDayValues');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded, values);
    });

    // Phase 4 (docs/scheduling-v2-spec.md, "Implementation order"):
    // replan() needs preferredWakeUpTime/maxDailyDelta from AppState directly (FR-3) -
    // Phase 0 deliberately added only the 4 fields that don't need a settings
    // UI first (lastEffectiveWakeTime is derived from pendingDayValues
    // instead, see replan_test.dart); these two are added now, following the
    // exact same persistence pattern as the others.
    test('preferredWakeUpTime (FR-3/FR-4) - no default value, revisable to null', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.preferredWakeUpTime, isNull);

      first.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 30);
      final second = AppState();
      await second.initialized;
      expect(second.preferredWakeUpTime, const TimeOfDay(hour: 7, minute: 30));

      second.preferredWakeUpTime = null;
      final third = AppState();
      await third.initialized;
      expect(third.preferredWakeUpTime, isNull);
    });

    // FR-16/Phase 5 step 22: checkpoint 2 runs in the background isolate
    // without AppState and must be able to tell which daily values are
    // instant-anchored and which are digit-anchored - hence persisted, with
    // the same directly-readable-via-SharedPreferences format as
    // pendingDayValues.
    test('pendingDayInstantAnchored (FR-16) - readable via AppState and directly', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.pendingDayInstantAnchored, isEmpty);

      final anchored = <String, bool>{
        '2026-01-16': true, // the value came directly from a real hardFloor
        '2026-01-17': false, // preferredWakeUpTime/the curve
      };
      first.pendingDayInstantAnchored = anchored;

      final second = AppState();
      await second.initialized;
      expect(second.pendingDayInstantAnchored, anchored);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pendingDayInstantAnchored');
      expect(raw, isNotNull);
      expect(jsonDecode(raw!), anchored);
    });

    // docs/TODO.md T-96: the gentle-wake ramp duration was hardcoded in
    // app_state.dart as `Duration(seconds: 60)`.
    test('gentleWakeUpDuration - round-trip and enforced minimum', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      // Default 5 minutes, gentle wake-up itself on by default (maintainer
      // request).
      expect(first.gentleWakeUpEnabled, isTrue);
      expect(first.gentleWakeUpDuration, const Duration(minutes: 5));

      first.gentleWakeUpDuration = const Duration(minutes: 10);
      final second = AppState();
      await second.initialized;
      expect(second.gentleWakeUpDuration, const Duration(minutes: 10));

      // The hh:mm picker on the sleep-habits screen allows 00:00, and
      // assertions are off in the release build - so a zero would reach the
      // plugin unchecked (T-175: now VolumeSettings.staircaseFade, which
      // needs at least one fade step). Hence the same bound as for
      // maxDailyDelta.
      second.gentleWakeUpDuration = Duration.zero;
      expect(second.gentleWakeUpDuration, const Duration(minutes: 1));
    });

    // docs/TODO.md T-52.3: durationToGetReady used to be one single global
    // value with no per-weekday override.
    test('durationToGetReadyForWeekday - falls back to the global value until overridden, round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      first.durationToGetReady = const TimeOfDay(hour: 0, minute: 30);

      // No override yet - every day falls back to the global value.
      for (final day in DayOfWeek.values) {
        expect(first.durationToGetReadyForWeekday(day),
            const TimeOfDay(hour: 0, minute: 30));
      }

      first.setDurationToGetReadyForWeekday(
          DayOfWeek.monday, const TimeOfDay(hour: 1, minute: 15));

      expect(first.durationToGetReadyForWeekday(DayOfWeek.monday),
          const TimeOfDay(hour: 1, minute: 15));
      // Every other day is unaffected.
      expect(first.durationToGetReadyForWeekday(DayOfWeek.tuesday),
          const TimeOfDay(hour: 0, minute: 30));

      final second = AppState();
      await second.initialized;
      expect(second.durationToGetReadyForWeekday(DayOfWeek.monday),
          const TimeOfDay(hour: 1, minute: 15));
      expect(second.durationToGetReadyForWeekday(DayOfWeek.tuesday),
          const TimeOfDay(hour: 0, minute: 30));

      // Clearing the override (value: null) reverts to following the global
      // value, rather than freezing Monday at whatever it was.
      second.setDurationToGetReadyForWeekday(DayOfWeek.monday, null);
      expect(second.durationToGetReadyForWeekday(DayOfWeek.monday),
          const TimeOfDay(hour: 0, minute: 30));
    });

    // docs/TODO.md T-52.1: there used to be no way to opt out of FR-4's
    // drift/hold on days with no calendar entry - it was the only behaviour.
    test('scheduleOnGapDays - defaults to true (the previous, only behaviour), round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.scheduleOnGapDays, isTrue);

      first.scheduleOnGapDays = false;
      final second = AppState();
      await second.initialized;
      expect(second.scheduleOnGapDays, isFalse);
    });

    test('maxDailyDelta (FR-3) - default 1 hour, minimum of 15 minutes enforced', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.maxDailyDelta, const Duration(hours: 1)); // maintainer request

      first.maxDailyDelta = const Duration(minutes: 45);
      final second = AppState();
      await second.initialized;
      expect(second.maxDailyDelta, const Duration(minutes: 45));

      // An attempt to go below the minimum is raised to 15min.
      second.maxDailyDelta = const Duration(minutes: 5);
      expect(second.maxDailyDelta, const Duration(minutes: 15));
    });
  });

  group('FR-3 fields without a round-trip test (T-108)', () {
    // The 2026-09 review found three of the ten FR-3 fields with no
    // persistence round-trip. They are used functionally in replan_test,
    // checkpoint_test, and replan_notifications_test - but none of those
    // rebuild AppState, so none of them ever check whether the value
    // survives an app restart. Both bool markers carry FR-6's and FR-9's
    // "once" promise across exactly this boundary.

    test('lastProcessedConcludedDay (FR-9, T-75)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.lastProcessedConcludedDay, isNull);

      final day = DateTime.utc(2026, 3, 10);
      first.lastProcessedConcludedDay = day;

      final second = AppState();
      await second.initialized;
      expect(second.lastProcessedConcludedDay, day);
    });

    test('lastProcessedConcludedDay is independent of lastReplanDate (T-75)',
        () async {
      // The actual point of T-75: the two must not merge back into a single value.
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;

      first.lastProcessedConcludedDay = DateTime.utc(2026, 3, 10);
      first.lastReplanDate = DateTime.utc(2026, 3, 11);

      final second = AppState();
      await second.initialized;
      expect(second.lastProcessedConcludedDay, DateTime.utc(2026, 3, 10));
      expect(second.lastReplanDate, DateTime.utc(2026, 3, 11));
    });

    test('overrunNotificationSent (FR-6, T-74a)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.overrunNotificationSent, isFalse);

      first.overrunNotificationSent = true;

      final second = AppState();
      await second.initialized;
      expect(second.overrunNotificationSent, isTrue,
          reason: 'FR-6 "once" must survive a restart');
    });

    test('safetyValveNotificationSent (FR-9, T-81)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.safetyValveNotificationSent, isFalse);

      first.safetyValveNotificationSent = true;

      final second = AppState();
      await second.initialized;
      expect(second.safetyValveNotificationSent, isTrue,
          reason: 'FR-9 "once" must survive a restart');
    });
  });

  group('diagnostics switch (T-135)', () {
    test('diagnosticsIncludeClockTimes: off by default, round-trip holds',
        () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.diagnosticsIncludeClockTimes, isFalse,
          reason: 'the default is the load-bearing guarantee: without '
              'explicitly switching it on, the log contains no clock values');

      first.diagnosticsIncludeClockTimes = true;

      final second = AppState();
      await second.initialized;
      expect(second.diagnosticsIncludeClockTimes, isTrue);
    });

    test('the general diagnostics switch stays independent of it', () async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState();
      await appState.initialized;

      appState.diagnosticsIncludeClockTimes = true;
      expect(appState.diagnosticsEnabled, isFalse,
          reason: 'off by default (T-173, maintainer request)');
      appState.diagnosticsEnabled = true;
      expect(appState.diagnosticsIncludeClockTimes, isTrue,
          reason: 'two separate switches - one does not flip the other');
    });
  });
}
