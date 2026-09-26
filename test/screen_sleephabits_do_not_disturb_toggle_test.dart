// docs/TODO.md T-190 (maintainer device report): turning the Sleep Habits
// "Do Not Disturb" toggle OFF used to only restore the device's previous
// interruption filter IF one was still remembered (`doNotDisturbPreviousFilterKey`
// present) - a no-op otherwise. Reachable in practice after an app reinstall
// wipes all SharedPreferences (the maintainer's own real case) while the
// device's actual Do Not Disturb state, which lives entirely outside app
// data, is untouched by that: the toggle then had no way left to turn the
// real state back off at all. A manual "turn the whole feature off" tap is
// now guaranteed to force Do Not Disturb off (`interruptionFilterAll`)
// whenever nothing is remembered to restore to instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/sleep_habits/screen_sleephabits.dart';
import 'package:crescendo_alarm/utils/do_not_disturb.dart'
    show doNotDisturbPreviousFilterKey;
import 'package:crescendo_alarm/utils/do_not_disturb_channel.dart';

Future<AppState> _pumpScreen(WidgetTester tester,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final appState = AppState();
  await appState.initialized;
  appState.doNotDisturbEnabled = true;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSleephabits()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

Future<void> _tapToggle(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SwitchListTile, label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  final realSetInterruptionFilter = setInterruptionFilter;
  tearDown(() {
    setInterruptionFilter = realSetInterruptionFilter;
  });

  testWidgets(
      'turning it off with a remembered previous filter: restores to that '
      'exact value', (tester) async {
    await _pumpScreen(tester, prefs: {
      doNotDisturbPreviousFilterKey: interruptionFilterPriority,
    });
    final applied = <int>[];
    setInterruptionFilter = (f) async {
      applied.add(f);
      return true;
    };

    await _tapToggle(tester, 'Do Not Disturb');

    expect(applied, [interruptionFilterPriority],
        reason: 'the device\'s own previous state must be restored '
            'exactly, not blasted to "off" when something legitimate was '
            'actually remembered');
  });

  testWidgets(
      'turning it off with NOTHING remembered to restore to (e.g. after an '
      'app reinstall wiped SharedPreferences): forces Do Not Disturb off '
      'entirely instead of doing nothing', (tester) async {
    await _pumpScreen(tester); // no doNotDisturbPreviousFilterKey at all
    final applied = <int>[];
    setInterruptionFilter = (f) async {
      applied.add(f);
      return true;
    };

    await _tapToggle(tester, 'Do Not Disturb');

    expect(applied, [interruptionFilterAll],
        reason: 'a manual "turn this whole feature off" tap must not leave '
            'the device silently stuck just because there is nothing left '
            'to restore to');
  });
}
