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
import 'package:crescendo_alarm/screens/settings/page_alarm_screen.dart';
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;

// docs/TODO.md T-240: Settings > Alarm Screen tells the user whether the
// alarm screen can open by itself and where to change it.

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: Scaffold(body: PageAlarmScreen())),
    ),
  );
  await tester.pumpAndSettle();
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
    access.readAlarmScreenAccess = () async => access.AlarmScreenAccess.unavailable;
  });

  testWidgets('both allowed: says so and offers no button', (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: true, overlay: true);

    await _pump(tester);

    expect(find.text('Over the lock screen'), findsOneWidget);
    expect(find.text('On an unlocked phone'), findsOneWidget);
    expect(find.textContaining('Allowed'), findsNWidgets(2));
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('full-screen intent denied: warns and opens its system screen',
      (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: false, overlay: true);

    await _pump(tester);

    expect(find.textContaining('only as a notification'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open settings'));
    await tester.pump();

    expect(opened, ['fullScreenIntent']);
  });

  testWidgets('overlay not allowed: explains and opens its system screen',
      (tester) async {
    access.readAlarmScreenAccess = () async =>
        const access.AlarmScreenAccess(fullScreenIntent: null, overlay: false);

    await _pump(tester);

    expect(find.textContaining('Not needed on this Android version'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
    await tester.pump();

    expect(opened, ['overlay']);
  });

  testWidgets('without a native side the page says it is unavailable',
      (tester) async {
    access.readAlarmScreenAccess = () async => access.AlarmScreenAccess.unavailable;

    await _pump(tester);

    expect(find.textContaining('not available on this device'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('returning from the system screen re-reads the status',
      (tester) async {
    var overlay = false;
    access.readAlarmScreenAccess = () async =>
        access.AlarmScreenAccess(fullScreenIntent: true, overlay: overlay);

    await _pump(tester);
    expect(find.widgetWithText(FilledButton, 'Allow'), findsOneWidget);

    overlay = true; // granted in the system settings
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Allow'), findsNothing);
  });
}
