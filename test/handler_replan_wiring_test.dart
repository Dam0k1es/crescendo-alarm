import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/screens/alarms/screen_active_alarm.dart';

// Phase 5 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge", Schritt
// 19): Handler.handleAlarm() -> runAlarmRingCheckpoint(). FR-8 sagt, der Ring
// selbst "feuert immer" und muss einen Checkpoint auslösen - das darf aber
// NIE den Alarm-Overlay bzw. den 3s-Fallback-Pfad verzögern oder brechen; das
// ist genau die Regression, die diese Datei absichert.

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

/// docs/TODO.md T-73: der Replan-Checkpoint feuert nur noch für einen
/// klingelnden `ScheduledAlarm`. Damit die Nicht-Blockier-Tests unten den
/// Checkpoint überhaupt erreichen, muss der Alarm in AppState registriert sein.
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
      'ein hängender Checkpoint (nie abschließend) verzögert das Zeigen des Alarm-Overlays nicht',
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

    // Sauber aufräumen, damit kein offenes Future über das Testende
    // hinausreicht.
    completer.complete(_fixedResult);
    await tester.pump();
  });

  testWidgets(
      'ein Checkpoint, der fehlschlägt, verhindert das Zeigen des Overlays nicht',
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
      'T-73: ein klingelnder ManualAlarm löst KEINEN Replan-Checkpoint aus',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    // Derselbe Id wie der klingelnde Alarm - aber als ManualAlarm.
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

    // FR-15: ein manueller Alarm darf die ScheduledAlarm-Kette nicht
    // fortschreiben (Fenster, gapDayCounter, lastReplanDate).
    expect(called, isFalse);
    // Das Overlay muss trotzdem erscheinen.
    expect(find.byType(ScreenAlarmActive), findsOneWidget);
  });

  testWidgets(
      'runCheckpoint wird tatsächlich mit der AppState-Instanz aufgerufen',
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
