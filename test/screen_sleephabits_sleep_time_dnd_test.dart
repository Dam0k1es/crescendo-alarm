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

// docs/TODO.md T-198 (R6): "Der DND Trigger soll in den Sleep Habits
// aktiviert und deaktiviert werden können (default off)." Turning it on
// needs Android's "Do Not Disturb access"; without it the switch stays off
// and says why, rather than claiming a feature that cannot act.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/sleep_habits/screen_sleephabits.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/permissions.dart' as permissions;
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart' as sleep_time_dnd;

const _label = 'Do Not Disturb';

void main() {
  final pushedEnabled = <bool>[];
  var accessRequests = 0;

  setUp(() {
    pushedEnabled.clear();
    accessRequests = 0;
    sleep_time_dnd.pushSleepTimeWindow =
        ({required bool enabled, required sleep_time_dnd.SleepTimeWindow? window}) async {
      pushedEnabled.add(enabled);
      return const sleep_time_dnd.SleepTimeDndReport(
          decision: sleep_time_dnd.SleepTimeDndDecision.scheduled);
    };
  });

  tearDown(() {
    sleep_time_dnd.pushSleepTimeWindow =
        sleep_time_dnd.defaultPushSleepTimeWindow;
    permissions.requestDoNotDisturbAccess =
        permissions.requestDoNotDisturbAccessDefault;
  });

  Future<AppState> pump(WidgetTester tester,
      {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final appState = AppState();
    await appState.initialized;
    Diag.resetForTest();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(home: ScreenSleephabits()),
      ),
    );
    await tester.pumpAndSettle();
    pushedEnabled.clear();
    return appState;
  }

  Future<void> tapToggle(WidgetTester tester) async {
    final finder = find.widgetWithText(SwitchListTile, _label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, _label))
      .value;

  testWidgets('shows a Do Not Disturb switch in Sleep Habits, off by default',
      (tester) async {
    await pump(tester);
    expect(find.widgetWithText(SwitchListTile, _label), findsOneWidget);
    expect(switchValue(tester), isFalse);
  });

  testWidgets('with Do Not Disturb access: turning it on enables and arms it',
      (tester) async {
    permissions.requestDoNotDisturbAccess = () async {
      accessRequests++;
      return true;
    };
    final appState = await pump(tester);

    await tapToggle(tester);

    expect(accessRequests, 1);
    expect(appState.sleepTimeDndEnabled, isTrue);
    expect(switchValue(tester), isTrue);
    expect(pushedEnabled, contains(true));
    expect(
        Diag.records
            .where((r) => r.event == DiagEvent.sleepHabitChanged)
            .map((r) => r.fields[DiagField.sleepHabitSetting]),
        [DiagSleepHabitSetting.sleepTimeDndEnabled.code]);
  });

  testWidgets(
      'without Do Not Disturb access: stays off, arms nothing, and says why',
      (tester) async {
    permissions.requestDoNotDisturbAccess = () async {
      accessRequests++;
      return false;
    };
    final appState = await pump(tester);

    await tapToggle(tester);

    expect(accessRequests, 1);
    expect(appState.sleepTimeDndEnabled, isFalse);
    expect(switchValue(tester), isFalse);
    expect(pushedEnabled, isNot(contains(true)));
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
      'turning it off needs no access check and pushes "disabled" (R6: the '
      'native side then leaves Do Not Disturb if it had switched it on)',
      (tester) async {
    permissions.requestDoNotDisturbAccess = () async {
      accessRequests++;
      return false;
    };
    final appState =
        await pump(tester, prefs: {'sleepTimeDndEnabled': true});
    expect(switchValue(tester), isTrue);

    await tapToggle(tester);

    expect(accessRequests, 0);
    expect(appState.sleepTimeDndEnabled, isFalse);
    expect(pushedEnabled, [false]);
  });
}
