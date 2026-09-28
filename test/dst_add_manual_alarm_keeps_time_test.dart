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

// docs/TODO.md T-202: `AppState.addAlarm` rebuilt the stored ManualAlarm's
// TimeOfDay from the RESOLVED next occurrence (`alarmDateTime.hour/minute`).
// On a spring-forward day that rewrote the user's alarm for good: 02:30 in
// the skipped hour was resolved by Dart to 03:30 and saved as 03:30 - and
// with TZ-1's resolution it would be saved as 03:00. The resolution decides
// when THIS ring happens; the alarm's own reading must stay 02:30 for every
// later day.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';

import 'support/local_zone_transitions.dart';

void main() {
  final gaps = localTransitions().where((t) => t.isGap).toList();

  test('adding an alarm whose reading is skipped today keeps its reading', () async {
    for (final t in gaps) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final appState = AppState();
      await appState.initialized;
      final f = wallFields(t.wallMiddleMs);
      final time = TimeOfDay(hour: f.hour, minute: f.minute);

      // Switched off, so nothing reaches the (channel-less) alarm plugin -
      // the reading is persisted either way.
      await appState.addAlarm(
        ManualAlarm(time: time, enabled: false, id: 11),
        now: () => DateTime.fromMillisecondsSinceEpoch(
            t.instantMs - 3 * 60 * 60 * 1000),
      );

      expect(appState.manualAlarms.single.time, time, reason: '$t');
    }
  }, skip: gaps.isEmpty ? noTransitionReason : false);

  test('counter-test: an ordinary reading is stored unchanged', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;
    const time = TimeOfDay(hour: 7, minute: 15);
    await appState.addAlarm(ManualAlarm(time: time, enabled: false, id: 12),
        now: () => DateTime(2026, 7, 10, 5, 0));
    expect(appState.manualAlarms.single.time, time);
  });
}
