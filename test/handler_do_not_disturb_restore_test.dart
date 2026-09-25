import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';

// docs/TODO.md T-184 (maintainer request): "ab dem Wecker (nach snooze
// time, nur finaler Alarm) wieder auf den Zustand vorher... setzen" - Do
// Not Disturb must be restored exactly when a ring is the FINAL one (no
// further snooze could still postpone it), generalized from T-179's same
// concept (there, for gentle wake) to the very first ring too, not only a
// snoozed one.

const _fixedResult = ReplanResult(
  overrunNotificationNeeded: false,
  safetyValveTriggered: false,
  possiblyMissedAppointment: false,
);

AlarmSettings _fakeAlarmSettings({required int id, required DateTime dateTime}) =>
    AlarmSettings(
      id: id,
      dateTime: dateTime,
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(
        title: 'Test alarm',
        body: 'ringing',
      ),
    );

void _registerScheduledAlarm(AppState appState, {required int id}) {
  appState.scheduledAlarms = [
    ScheduledAlarm(
      time: DateTime.now().add(const Duration(minutes: 1)),
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    ),
  ];
}

Future<BuildContext> _pumpAppWithContext(
    WidgetTester tester, AppState appState) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return capturedContext;
}

void main() {
  testWidgets('snooze disabled: the very first ring is already final - '
      'restores immediately', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.snoozeEnabled = false;
    final ringTime = DateTime.now().add(const Duration(seconds: 1));
    _registerScheduledAlarm(appState, id: 1);
    final context = await _pumpAppWithContext(tester, appState);

    var restoreCalled = false;
    final handler = Handler(
      context,
      runCheckpoint: (_) async => _fixedResult,
      restoreDoNotDisturb: (a) async {
        restoreCalled = true;
        return true;
      },
    );

    await handler.handleAlarm(_fakeAlarmSettings(id: 1, dateTime: ringTime));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(restoreCalled, isTrue);
  });

  testWidgets('snooze enabled, budget remains: the first ring is NOT final - '
      'does not restore yet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.snoozeEnabled = true;
    appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 15);
    appState.snoozeTime = const Duration(minutes: 5);
    final ringTime = DateTime.now().add(const Duration(seconds: 1));
    _registerScheduledAlarm(appState, id: 2);
    final context = await _pumpAppWithContext(tester, appState);

    var restoreCalled = false;
    final handler = Handler(
      context,
      runCheckpoint: (_) async => _fixedResult,
      restoreDoNotDisturb: (a) async {
        restoreCalled = true;
        return true;
      },
    );

    await handler.handleAlarm(_fakeAlarmSettings(id: 2, dateTime: ringTime));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(restoreCalled, isFalse,
        reason: 'another snooze from this exact ring would still fit the '
            '15-minute budget - this is not the final ring yet');
  });

  testWidgets(
      'a snoozed re-ring that exhausts the budget IS final - restores',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.snoozeEnabled = true;
    appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 5);
    appState.snoozeTime = const Duration(minutes: 5);
    _registerScheduledAlarm(appState, id: 3);
    final context = await _pumpAppWithContext(tester, appState);

    // Simulate: the alarm originally rang 5 minutes ago (origin), and this
    // ring (the snoozed re-ring, a different platform id) is happening
    // right now - exactly at the edge of the 5-minute budget, so a further
    // snooze from here would exceed it.
    final origin = DateTime.now().subtract(const Duration(minutes: 5));
    appState.rememberSnoozeOrigin(3, origin);
    final ringTime = DateTime.now().add(const Duration(seconds: 1));

    var restoreCalled = false;
    final handler = Handler(
      context,
      runCheckpoint: (_) async => _fixedResult,
      restoreDoNotDisturb: (a) async {
        restoreCalled = true;
        return true;
      },
    );

    await handler.handleAlarm(_fakeAlarmSettings(id: 3, dateTime: ringTime));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(restoreCalled, isTrue);
  });

  testWidgets('receives the AppState instance', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.snoozeEnabled = false;
    _registerScheduledAlarm(appState, id: 4);
    final context = await _pumpAppWithContext(tester, appState);

    AppState? received;
    final handler = Handler(
      context,
      runCheckpoint: (_) async => _fixedResult,
      restoreDoNotDisturb: (a) async {
        received = a;
        return true;
      },
    );

    await handler.handleAlarm(_fakeAlarmSettings(
        id: 4, dateTime: DateTime.now().add(const Duration(seconds: 1))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(received, same(appState));
  });
}
