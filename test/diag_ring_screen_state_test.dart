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

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;
import 'package:crescendo_alarm/utils/diag/diag_log.dart';

// docs/TODO.md T-240 follow-up: when an alarm rings without a screen, the
// next question is "what state was the phone in?". The native launcher knows
// (locked? screen on? app in front? which accesses? what did it decide?);
// Dart records it with every ring - numbers only, no time, no title.

AlarmSettings _alarm() => AlarmSettings(
      id: 7,
      dateTime: DateTime.now(),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings:
          const NotificationSettings(title: 'Test alarm', body: 'ringing'),
    );

void main() {
  setUp(() {
    Diag.resetForTest();
  });

  tearDown(() {
    access.readLastRingScreenState = (after) async => null;
  });

  test('Diag.ringScreenState records the state as numbers', () async {
    SharedPreferences.setMockInitialValues({});
    await Diag.init(isolate: LogIsolate.main, enabled: true);

    Diag.ringScreenState(
      decision: RingLaunchDecision.skippedNoPermission,
      keyguardLocked: false,
      screenOn: true,
      appInFront: false,
      overlayGranted: false,
      fullScreenIntent: AccessState.denied,
    );

    final r = Diag.records.single;
    expect(r.event, DiagEvent.ringScreenState);
    expect(r.fields[DiagField.ringLaunchDecision],
        RingLaunchDecision.skippedNoPermission.code);
    expect(r.fields[DiagField.ringKeyguardLocked], 0);
    expect(r.fields[DiagField.ringScreenOn], 1);
    expect(r.fields[DiagField.ringAppInFront], 0);
    expect(r.fields[DiagField.ringOverlayGranted], 0);
    expect(r.fields[DiagField.ringFullScreenIntent], AccessState.denied.code);
  });

  test('the decision codes are the ones the native side sends', () {
    // Kept equal to RingScreenLaunchPolicy.Decision.code (Kotlin) by
    // test/alarm_screen_contract_test.dart.
    expect({for (final d in RingLaunchDecision.values) d.name: d.code}, {
      'unknown': 0,
      'launched': 1,
      'skippedLocked': 2,
      'skippedScreenOff': 3,
      'skippedAlreadyInFront': 4,
      'skippedNoPermission': 5,
      'launchFailed': 6,
      'launchNotShown': 7,
    });
  });

  testWidgets('every ring records the native launcher\'s state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Diag.init(isolate: LogIsolate.main, enabled: true);
    access.readLastRingScreenState = (after) async => const access.RingScreenState(
          ringId: 1,
          decisionCode: 5,
          keyguardLocked: false,
          screenOn: true,
          appInFront: false,
          overlayGranted: false,
          fullScreenIntent: false,
        );
    final appState = AppState();
    await appState.initialized;
    late BuildContext context;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ),
    ));
    final handler = Handler(
      context,
      runCheckpoint: (_) async => null,
      sleep: (d) async {},
      isRinging: (id) async => true,
      stopAlarm: (id) async => true,
    );

    await handler.handleAlarm(_alarm());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    final r = Diag.records.where((e) => e.event == DiagEvent.ringScreenState);
    expect(r, hasLength(1));
    expect(r.single.fields[DiagField.ringLaunchDecision], 5);
    expect(r.single.fields[DiagField.ringFullScreenIntent],
        AccessState.denied.code);
  });

  testWidgets('without a native answer the ring is still recorded, as unknown',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Diag.init(isolate: LogIsolate.main, enabled: true);
    access.readLastRingScreenState = (after) async => null;
    final appState = AppState();
    await appState.initialized;
    late BuildContext context;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ),
    ));
    final handler = Handler(
      context,
      runCheckpoint: (_) async => null,
      sleep: (d) async {},
      isRinging: (id) async => true,
      stopAlarm: (id) async => true,
    );

    await handler.handleAlarm(_alarm());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    final r = Diag.records.where((e) => e.event == DiagEvent.ringScreenState);
    expect(r, hasLength(1));
    expect(r.single.fields[DiagField.ringLaunchDecision],
        RingLaunchDecision.unknown.code);
  });

  testWidgets('a state that is not newer than the last recorded ring is never '
      'recorded as that ring\'s', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Diag.init(isolate: LogIsolate.main, enabled: true);
    final asked = <int>[];
    access.readLastRingScreenState = (after) async {
      asked.add(after);
      // The native side has nothing newer: it answers with the old ring.
      return const access.RingScreenState(
        ringId: 1,
        decisionCode: 1,
        keyguardLocked: false,
        screenOn: true,
        appInFront: true,
        overlayGranted: true,
        fullScreenIntent: null,
      );
    };
    final appState = AppState();
    await appState.initialized;
    late BuildContext context;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ),
    ));
    Handler.debugResetRecordedRing();
    final handler = Handler(
      context,
      runCheckpoint: (_) async => null,
      sleep: (d) async {},
      isRinging: (id) async => true,
      stopAlarm: (id) async => true,
    );

    await handler.handleAlarm(_alarm());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await handler.handleAlarm(_alarm());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    final r = Diag.records
        .where((e) => e.event == DiagEvent.ringScreenState)
        .map((e) => e.fields[DiagField.ringLaunchDecision])
        .toList();
    expect(asked, [0, 1], reason: 'the second ring asks for something newer');
    expect(r, [1, RingLaunchDecision.unknown.code]);
  });
}
