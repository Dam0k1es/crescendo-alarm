import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';

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
      // Default = the previously hardcoded behaviour, so existing
      // installations don't suddenly sound different.
      expect(first.gentleWakeUpDuration, const Duration(minutes: 1));

      first.gentleWakeUpDuration = const Duration(minutes: 10);
      final second = AppState();
      await second.initialized;
      expect(second.gentleWakeUpDuration, const Duration(minutes: 10));

      // The alarm plugin has `assert(fadeDuration > Duration.zero)`. But the
      // hh:mm picker on the sleep-habits screen allows 00:00, and assertions
      // are off in the release build - so a zero would reach the plugin
      // unchecked. Hence the same bound as for maxDailyDelta.
      second.gentleWakeUpDuration = Duration.zero;
      expect(second.gentleWakeUpDuration, const Duration(minutes: 1));
    });

    test('maxDailyDelta (FR-3) - the system minimum of 15 minutes is enforced', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppState();
      await first.initialized;
      expect(first.maxDailyDelta, const Duration(minutes: 15)); // default = minimum

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
      expect(appState.diagnosticsEnabled, isTrue);
      appState.diagnosticsEnabled = false;
      expect(appState.diagnosticsIncludeClockTimes, isTrue,
          reason: 'two separate switches - one does not flip the other');
    });
  });
}
