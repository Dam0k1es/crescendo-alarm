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

// docs/TODO.md T-198 (R5): "Ein manueller Alarm soll durch einen Schalter von
// der Schlafenszeit ausgenommen werden können." A manual alarm counts by
// default; the switch excludes it. The field must survive every path a
// ManualAlarm is copied through - T-191's predecessor field
// (`countsForDoNotDisturb`) was silently dropped by AppState.addAlarm's
// reconstruction once, and a v1.3.0 install still stores that old key.

import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart' as sleep_time_dnd;

void main() {
  group('ManualAlarm.excludeFromSleepTime', () {
    test('defaults to false - a manual alarm counts unless switched off', () {
      final alarm = ManualAlarm(time: const TimeOfDay(hour: 6, minute: 0));
      expect(alarm.excludeFromSleepTime, isFalse);
    });

    test('survives a toJson/fromJson round trip', () {
      final alarm = ManualAlarm(
          time: const TimeOfDay(hour: 6, minute: 0),
          excludeFromSleepTime: true,
          id: 42);
      final restored = ManualAlarm.fromJson(alarm.toJson());
      expect(restored.excludeFromSleepTime, isTrue);
      expect(restored, alarm);
    });

    test('missing from stored JSON (alarm saved before T-198) -> false', () {
      final json = jsonDecode(
              ManualAlarm(time: const TimeOfDay(hour: 6, minute: 0), id: 1)
                  .toJson())
          as Map<String, dynamic>
        ..remove('excludeFromSleepTime');
      expect(ManualAlarm.fromJson(jsonEncode(json)).excludeFromSleepTime,
          isFalse);
    });

    test(
        'a v1.3.0 alarm still carrying the removed countsForDoNotDisturb key '
        'parses, is not mistaken for the new field, and re-serialises '
        'without the old key', () {
      final json = jsonDecode(
              ManualAlarm(time: const TimeOfDay(hour: 6, minute: 0), id: 7)
                  .toJson())
          as Map<String, dynamic>
        ..remove('excludeFromSleepTime')
        // Both polarities of the old opt-in: neither may leak into the new
        // opt-out field, whose meaning is the opposite.
        ..['countsForDoNotDisturb'] = false;
      final fromFalse = ManualAlarm.fromJson(jsonEncode(json));
      expect(fromFalse.excludeFromSleepTime, isFalse);
      expect(fromFalse.toJson(), isNot(contains('countsForDoNotDisturb')));

      json['countsForDoNotDisturb'] = true;
      final fromTrue = ManualAlarm.fromJson(jsonEncode(json));
      expect(fromTrue.excludeFromSleepTime, isFalse);
    });

    test('equality and hashCode consider the field', () {
      final a = ManualAlarm(time: const TimeOfDay(hour: 6, minute: 0), id: 3);
      final b = ManualAlarm(
          time: const TimeOfDay(hour: 6, minute: 0),
          id: 3,
          excludeFromSleepTime: true);
      final aAgain =
          ManualAlarm(time: const TimeOfDay(hour: 6, minute: 0), id: 3);
      // repeatOnDays defaults to "every day" for all three, so only the new
      // field differs between a and b.
      expect(a == b, isFalse);
      expect(a == aAgain, isTrue);
      expect(a.hashCode == b.hashCode, isFalse);
    });
  });

  group('AppState keeps the field (the T-191 reconstruction trap)', () {
    setUp(() {
      // The channel has no native side in flutter test; capture pushes
      // instead so nothing reaches a MethodChannel.
      sleep_time_dnd.pushSleepTimeWindow =
          ({required bool enabled, required sleep_time_dnd.SleepTimeWindow? window}) async =>
              const sleep_time_dnd.SleepTimeDndReport(
                  decision: sleep_time_dnd.SleepTimeDndDecision.disabled);
    });
    tearDown(() {
      sleep_time_dnd.pushSleepTimeWindow = sleep_time_dnd.defaultPushSleepTimeWindow;
    });

    test('addAlarm carries excludeFromSleepTime into the stored alarm',
        () async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState();
      await appState.initialized;

      await appState.addAlarm(ManualAlarm(
        time: const TimeOfDay(hour: 6, minute: 0),
        // Disabled, so addAlarm does not reach the real alarm plugin.
        enabled: false,
        excludeFromSleepTime: true,
        id: 11,
      ));

      expect(appState.manualAlarms.single.excludeFromSleepTime, isTrue);

      // And through persistence: a fresh AppState reading the same prefs.
      final reloaded = AppState(
          getPrefsInstance: () async => SharedPreferences.getInstance());
      await reloaded.initialized;
      expect(reloaded.manualAlarms.single.excludeFromSleepTime, isTrue);
    });

    // updateAlarm is not driven here: it always calls removeAlarm ->
    // Alarm.stop, whose AlarmStorage never finishes initialising without the
    // real plugin, so the call cannot complete in flutter test (the same
    // reason no other test in this suite drives it). It also has no
    // reconstruction to drop a field from - it stores the dialog's alarm
    // object as-is (`_manualAlarms[index] = newAlarm`), which T-191 already
    // checked for its predecessor field.
  });
}
