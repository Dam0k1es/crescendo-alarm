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

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';

// docs/TODO.md T-240 follow-up: the one-time offer to let the alarm screen
// open by itself is shown once, then never again.

void main() {
  test('the prompt has not been shown on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;

    expect(appState.alarmScreenPromptShown, isFalse);
  });

  test('once marked it stays shown across a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;

    appState.markAlarmScreenPromptShown();
    expect(appState.alarmScreenPromptShown, isTrue);

    final restarted = AppState();
    await restarted.initialized;
    expect(restarted.alarmScreenPromptShown, isTrue);
  });
}
