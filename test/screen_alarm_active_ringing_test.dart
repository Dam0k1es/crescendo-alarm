import 'dart:async';

import 'package:alarm/model/alarm_settings.dart';
import 'package:alarm/model/notification_settings.dart';
import 'package:alarm/model/volume_settings.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/alarms/screen_active_alarm.dart';

// Bug report: an alarm deactivated via the notification (no app UI open)
// left ScreenAlarmActive stuck showing on reopen, with nothing actually
// ringing and no way out (`PopScope(canPop: false)`). The fix: the screen
// watches `Alarm.ringing` (injected here via [ScreenAlarmActive
// .debugRingingStreamOverride]) and pops itself once its own alarm id is no
// longer in the ringing set.

AlarmSettings _fakeAlarmSettings(int id) => AlarmSettings(
      id: id,
      dateTime: DateTime.now(),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(title: 't', body: 'b'),
    );

Future<void> _pumpScreen(WidgetTester tester, AppState appState,
    {int alarmId = 1}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ScreenAlarmActive(alarmId: alarmId),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Not pumpAndSettle: ScreenAlarmActive runs a Timer.periodic (the clock
  // display) that never completes on its own, which would hang settle
  // forever - matching test/handler_replan_wiring_test.dart's approach.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ScreenAlarmActive), findsOneWidget);
}

void main() {
  late StreamController<AlarmSet> ringing;

  setUp(() {
    ringing = StreamController<AlarmSet>.broadcast();
    ScreenAlarmActive.debugRingingStreamOverride = ringing.stream;
  });

  tearDown(() async {
    ScreenAlarmActive.debugRingingStreamOverride = null;
    await ringing.close();
  });

  testWidgets(
      'closes itself once its own alarm disappears from the ringing set',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    await _pumpScreen(tester, appState, alarmId: 1);

    ringing.add(AlarmSet([_fakeAlarmSettings(1)]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ScreenAlarmActive), findsOneWidget,
        reason: 'still ringing - must stay open');

    ringing.add(AlarmSet.empty());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ScreenAlarmActive), findsNothing,
        reason: 'the alarm was stopped elsewhere (e.g. notification swipe) - '
            'the screen must not get stuck');
  });

  testWidgets('an unrelated alarm disappearing does not close the screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    await _pumpScreen(tester, appState, alarmId: 1);

    ringing.add(AlarmSet([_fakeAlarmSettings(1), _fakeAlarmSettings(2)]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    ringing.add(AlarmSet([_fakeAlarmSettings(1)]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenAlarmActive), findsOneWidget);
  });

  testWidgets('the very first (seed-like) event does not auto-close',
      (tester) async {
    // Matches the real Alarm.ringing BehaviorSubject's semantics: the first
    // delivery is a snapshot, not a change, and must not be mistaken for a
    // disappearance just because nothing populated it yet.
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    await _pumpScreen(tester, appState, alarmId: 1);

    ringing.add(AlarmSet.empty());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenAlarmActive), findsOneWidget);
  });
}
