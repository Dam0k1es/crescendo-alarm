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
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;

// docs/TODO.md T-240 (Günther's review): the hint is tested on its own in
// alarm_screen_access_hint_test.dart; this pins that the Alarms screen really
// embeds it, and that it is silent where there is no native side - which is
// why every other ScreenAlarms test is unaffected.

Future<AppState> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ScreenAlarms()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  tearDown(() {
    access.readAlarmScreenAccess =
        () async => access.AlarmScreenAccess.unavailable;
  });

  testWidgets('the Alarms screen embeds the hint and shows its warning',
      (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: false, overlay: true);

    await _pumpScreen(tester);

    expect(find.byType(AlarmScreenAccessHint), findsOneWidget);
    expect(find.textContaining('only as a notification on the lock screen'),
        findsOneWidget);
  });

  testWidgets('with no native side the Alarms screen shows neither warning nor '
      'dialog', (tester) async {
    access.readAlarmScreenAccess =
        () async => access.AlarmScreenAccess.unavailable;

    await _pumpScreen(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('lock screen'), findsNothing);
  });

  testWidgets('the offer does not open over another screen that is on top, '
      'e.g. a ringing alarm\'s', (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: true, overlay: false);
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    // A route (the ring screen) is put on top first, then the hint is built
    // beneath it.
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('ringing'))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('over it'))));
    await tester.pumpAndSettle();

    // Build the hint inside a page that is NOT the top route.
    final host = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: AlarmScreenAccessHint()));
    navigator.currentState!.pushReplacement(host);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('ring screen on top'))));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(appState.alarmScreenPromptShown, isFalse,
        reason: 'not shown, so it is not used up');
  });
}
