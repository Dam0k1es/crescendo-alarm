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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/alarms/alarm_screen_access_hint.dart';
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;

// docs/TODO.md T-240 follow-up (Lea's review): nobody is told when the
// full-screen-intent access (Android 14+) is off, and nobody is offered the
// overlay access unless they happen to open Settings > Alarm Screen. The
// hint sits on the Alarms screen: a persistent warning for the first, a
// one-time offer for the second.

Future<AppState> _pump(WidgetTester tester, {AppState? existing}) async {
  AppState appState;
  if (existing != null) {
    appState = existing;
  } else {
    SharedPreferences.setMockInitialValues({});
    appState = AppState();
    await appState.initialized;
  }
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [AlarmScreenAccessHint()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  var opened = <String>[];

  setUp(() {
    opened = [];
    access.openFullScreenIntentSettings = () async {
      opened.add('fullScreenIntent');
      return true;
    };
    access.openOverlaySettings = () async {
      opened.add('overlay');
      return true;
    };
  });

  tearDown(() {
    access.readAlarmScreenAccess =
        () async => access.AlarmScreenAccess.unavailable;
  });

  testWidgets('full-screen intents denied: a persistent warning with a button',
      (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: false, overlay: true);

    await _pump(tester);

    expect(find.textContaining('only as a notification on the lock screen'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Open settings'));
    await tester.pump();
    expect(opened, ['fullScreenIntent']);
  });

  testWidgets('full-screen intents allowed, or nothing to grant: no warning',
      (tester) async {
    for (final granted in [true, null]) {
      access.readAlarmScreenAccess = () async => access.AlarmScreenAccess(
          fullScreenIntent: granted, overlay: true);
      await _pump(tester);
      expect(find.textContaining('lock screen'), findsNothing);
    }
  });

  testWidgets('no native side: neither warning nor offer', (tester) async {
    access.readAlarmScreenAccess =
        () async => access.AlarmScreenAccess.unavailable;

    await _pump(tester);

    expect(find.textContaining('lock screen'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the warning goes away when the access is granted meanwhile',
      (tester) async {
    var granted = false;
    access.readAlarmScreenAccess = () async => access.AlarmScreenAccess(
        fullScreenIntent: granted, overlay: true);
    await _pump(tester);
    expect(find.textContaining('lock screen'), findsOneWidget);

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.textContaining('lock screen'), findsNothing);
  });

  testWidgets('overlay not allowed and never offered: the offer appears once',
      (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: true, overlay: false);

    final appState = await _pump(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Open the alarm screen by itself?'), findsOneWidget);
    expect(appState.alarmScreenPromptShown, isTrue,
        reason: 'shown counts as shown, whatever the answer');

    await tester.tap(find.widgetWithText(TextButton, 'Not now'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, isEmpty);

    await _pump(tester, existing: appState);
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'never offered a second time');
  });

  testWidgets('answering Allow opens the overlay system screen',
      (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: true, overlay: false);

    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
    await tester.pumpAndSettle();

    expect(opened, ['overlay']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('no offer when the overlay is already allowed or it was shown '
      'before', (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: true, overlay: true);
    await _pump(tester);
    expect(find.byType(AlertDialog), findsNothing);

    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: true, overlay: false);
    SharedPreferences.setMockInitialValues({});
    final seen = AppState();
    await seen.initialized;
    seen.markAlarmScreenPromptShown();
    await _pump(tester, existing: seen);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
