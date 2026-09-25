import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/screens/alarms/screen_active_alarm.dart';

// Phase 5 (docs/scheduling-v2-spec.md, "Implementation order", step
// 19): Handler.handleAlarm() -> runAlarmRingCheckpoint(). FR-8 says the ring
// itself "always fires" and must trigger a checkpoint - but that must NEVER
// delay or break the alarm overlay or the 3s fallback path; that is exactly
// the regression this file guards against.

const _fixedResult = ReplanResult(
  overrunNotificationNeeded: false,
  safetyValveTriggered: false,
  possiblyMissedAppointment: false,
);

AlarmSettings _fakeAlarmSettings({int id = 1}) => AlarmSettings(
      id: id,
      dateTime: DateTime.now().add(const Duration(seconds: 1)),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(
        title: 'Test alarm',
        body: 'ringing',
      ),
    );

/// docs/TODO.md T-73: the replan checkpoint now only fires for a ringing
/// `ScheduledAlarm`. For the non-blocking tests below to reach the
/// checkpoint at all, the alarm must be registered in AppState.
void _registerScheduledAlarm(AppState appState, {int id = 1}) {
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
  testWidgets(
      'a hanging checkpoint (never completing) does not delay showing the alarm overlay',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    _registerScheduledAlarm(appState);
    final context = await _pumpAppWithContext(tester, appState);

    final completer = Completer<ReplanResult>();
    final handler = Handler(context, runCheckpoint: (_) => completer.future);

    await handler.handleAlarm(_fakeAlarmSettings());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenAlarmActive), findsOneWidget);

    // Clean up properly, so no open Future outlives the end of the test.
    completer.complete(_fixedResult);
    await tester.pump();
  });

  testWidgets(
      'a checkpoint that fails does not prevent the overlay from showing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    _registerScheduledAlarm(appState);
    final context = await _pumpAppWithContext(tester, appState);

    final handler = Handler(
      context,
      runCheckpoint: (_) async =>
          throw StateError('calendar plugin unavailable'),
    );

    await handler.handleAlarm(_fakeAlarmSettings());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenAlarmActive), findsOneWidget);
  });

  testWidgets(
      'T-73: a ringing ManualAlarm triggers NO replan checkpoint',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    // The same id as the ringing alarm - but as a ManualAlarm.
    appState.manualAlarms
        .add(ManualAlarm(time: const TimeOfDay(hour: 3, minute: 0), id: 1));
    final context = await _pumpAppWithContext(tester, appState);

    var called = false;
    final handler = Handler(context, runCheckpoint: (_) async {
      called = true;
      return _fixedResult;
    });

    await handler.handleAlarm(_fakeAlarmSettings());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // FR-15: a manual alarm must not advance the ScheduledAlarm chain
    // (window, gapDayCounter, lastReplanDate).
    expect(called, isFalse);
    // The overlay must still appear.
    expect(find.byType(ScreenAlarmActive), findsOneWidget);
  });

  testWidgets(
      'runCheckpoint is actually called with the AppState instance',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    _registerScheduledAlarm(appState);
    final context = await _pumpAppWithContext(tester, appState);

    AppState? received;
    final handler = Handler(context, runCheckpoint: (a) async {
      received = a;
      return _fixedResult;
    });

    await handler.handleAlarm(_fakeAlarmSettings());
    await tester.pump();

    expect(received, same(appState));
  });
}
