import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/alarm_ring_gate.dart';
import 'package:wakeywakey/models/alarms/handler.dart';

// docs/TODO.md T-39: the whole "guaranteed wake-up" gate used to hang off
// one Alarm.ringing subscription owned by _MyHomePageState - if that one
// screen widget was ever not mounted when an alarm rang, nothing enforced
// the scan requirement at all. AlarmRingGate moves ownership up to the app
// root (_MyAppState), which is not swapped out by anything MyApp.build()
// does (switching `home:` between SplashScreen and MyHomePage only changes
// what the Navigator shows), and is unit-testable on its own via an
// injected stream and handler factory - neither of which the original
// inline subscription in main.dart had.

AlarmSettings _fakeAlarm({required int id}) => AlarmSettings(
      id: id,
      dateTime: DateTime.now().add(const Duration(seconds: 1)),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(
        title: 'Test alarm',
        body: 'ringing',
      ),
    );

/// Records every alarm handed to `handleAlarm` instead of doing any of the
/// real work (showing an overlay, running a checkpoint, stopping the
/// platform alarm) - the same subclassing approach as
/// test/handler_overlay_retry_test.dart, since `Handler`'s constructor
/// itself needs a `Provider<AppState>` ancestor to succeed at all.
class _RecordingHandler extends Handler {
  _RecordingHandler(super.context)
      : super(runCheckpoint: (_) async => null, sleep: (_) async {});

  final List<AlarmSettings> handled = [];

  @override
  Future<void> handleAlarm(AlarmSettings event) async {
    handled.add(event);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Pumps a `MaterialApp` using [navigatorKey] as its own, so
  /// `navigatorKey.currentContext` becomes non-null - exactly what
  /// `_MyAppState.build()` does for the real `AlarmRingGate`.
  Future<void> pumpNavigator(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigatorKey,
    AppState appState,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const SizedBox(),
        ),
      ),
    );
  }

  test('does not fire before any Navigator context exists', () async {
    final navigatorKey = GlobalKey<NavigatorState>();
    expect(navigatorKey.currentContext, isNull,
        reason: 'the test setup itself must start with no context, or this '
            'proves nothing');

    final appState = AppState();
    await appState.initialized;
    final ringing = StreamController<AlarmSet>.broadcast();
    _RecordingHandler? built;
    final gate = AlarmRingGate(
      navigatorKey,
      ringingStream: ringing.stream,
      buildHandler: (context) => built = _RecordingHandler(context),
    );
    gate.start();

    ringing.add(AlarmSet([_fakeAlarm(id: 1)]));
    await Future<void>.delayed(Duration.zero);

    expect(built, isNull,
        reason: 'nothing to build a Handler against - there is no context '
            'yet, and a real ring cannot happen before the engine has run '
            'at least one frame');

    await ringing.close();
  });

  testWidgets(
      'dispatches a newly ringing alarm to Handler.handleAlarm once a '
      'context exists', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final appState = AppState();
    await appState.initialized;
    await pumpNavigator(tester, navigatorKey, appState);
    expect(navigatorKey.currentContext, isNotNull);

    final ringing = StreamController<AlarmSet>.broadcast();
    _RecordingHandler? handler;
    final gate = AlarmRingGate(
      navigatorKey,
      ringingStream: ringing.stream,
      buildHandler: (context) => handler = _RecordingHandler(context),
    );
    gate.start();

    final alarm = _fakeAlarm(id: 7);
    ringing.add(AlarmSet([alarm]));
    await tester.pump();

    expect(handler?.handled, [alarm]);

    await ringing.close();
  });

  testWidgets(
      'diffs against the previous set - a repeated event for the same '
      'still-ringing alarm is not dispatched twice', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final appState = AppState();
    await appState.initialized;
    await pumpNavigator(tester, navigatorKey, appState);

    final ringing = StreamController<AlarmSet>.broadcast();
    _RecordingHandler? handler;
    final gate = AlarmRingGate(
      navigatorKey,
      ringingStream: ringing.stream,
      buildHandler: (context) => handler = _RecordingHandler(context),
    );
    gate.start();

    final alarm = _fakeAlarm(id: 3);
    ringing.add(AlarmSet([alarm]));
    await tester.pump();
    // Alarm.ringing emits the full still-ringing set on every change, not
    // one event per newly-ringing alarm - so the same alarm reappearing
    // (e.g. some unrelated alarm elsewhere starting or stopping) must not
    // re-trigger handleAlarm.
    ringing.add(AlarmSet([alarm]));
    await tester.pump();

    expect(handler?.handled, [alarm],
        reason: 'exactly one dispatch for one alarm that never actually '
            'stopped ringing in between');

    await ringing.close();
  });

  testWidgets('dispatches each alarm exactly once when two ring together',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final appState = AppState();
    await appState.initialized;
    await pumpNavigator(tester, navigatorKey, appState);

    final ringing = StreamController<AlarmSet>.broadcast();
    _RecordingHandler? handler;
    final gate = AlarmRingGate(
      navigatorKey,
      ringingStream: ringing.stream,
      buildHandler: (context) => handler = _RecordingHandler(context),
    );
    gate.start();

    final first = _fakeAlarm(id: 1);
    final second = _fakeAlarm(id: 2);
    ringing.add(AlarmSet([first, second]));
    await tester.pump();

    expect(handler?.handled, unorderedEquals([first, second]));

    await ringing.close();
  });

  testWidgets('stop() cancels the subscription - no further dispatch',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final appState = AppState();
    await appState.initialized;
    await pumpNavigator(tester, navigatorKey, appState);

    final ringing = StreamController<AlarmSet>.broadcast();
    _RecordingHandler? handler;
    final gate = AlarmRingGate(
      navigatorKey,
      ringingStream: ringing.stream,
      buildHandler: (context) => handler = _RecordingHandler(context),
    );
    gate.start();
    gate.stop();

    ringing.add(AlarmSet([_fakeAlarm(id: 9)]));
    await tester.pump();

    expect(handler, isNull,
        reason: 'stop() must have cancelled the subscription before this '
            'event was ever delivered');

    await ringing.close();
  });
}
