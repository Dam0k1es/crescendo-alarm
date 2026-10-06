import 'dart:async';

import 'package:alarm/model/alarm_settings.dart';
import 'package:alarm/model/notification_settings.dart';
import 'package:alarm/model/volume_settings.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/models/scan_code/scan_result.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';
import 'package:crescendo_alarm/utils/notifications.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-215 and T-216: the QR gate's emergency stop (the T-38 escape
// hatch for a camera that cannot open the gate).
//
// T-215, maintainer (2026-10-06): "Der soll nicht verschwinden, aber
// wegwischbar sein." - once offered, a later successful camera
// re-initialisation must not withdraw it; only the user's own swipe hides it,
// and a new failure condition (a camera error, or another stretch without a
// valid code) offers it again.
//
// T-216, maintainer (2026-10-06): "Wieso? der soll nur den aktuellen
// canceln." - the emergency stop silences the ringing alarm only, never a
// future armed one, and a stopped repeating manual alarm is re-armed exactly
// like after a normal dismiss.

const _label = 'Camera not working - Stop alarm';

AlarmSettings _settings(int id, DateTime at) => AlarmSettings(
      id: id,
      dateTime: at,
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(title: 't', body: 'b'),
    );

ManualAlarm _manual(int id, {Map<DayOfWeek, bool>? repeatOnDays}) =>
    ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
      repeatOnDays: repeatOnDays,
    );

class _SilentNotifications implements Notifications {
  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async =>
      id ?? 1;

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

Future<AppState> _pumpScanner(
  WidgetTester tester, {
  int? alarmId,
  bool displayExitButton = false,
  void Function(AppState appState)? prepare,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  appState.deactivationCode = DeactivationCode(payload: 'right');
  prepare?.call(appState);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QrScanner(
                  alarmId: alarmId,
                  displayExitButton: displayExitButton,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(QrScanner), findsOneWidget);
  return appState;
}

Future<void> _swipeAway(WidgetTester tester) async {
  await tester.drag(find.text(_label), const Offset(600, 0));
  await tester.pumpAndSettle();
}

void main() {
  late StreamController<ScanResult> scans;
  late StreamController<Object?> cameraInits;
  late StreamController<AlarmSet> ringing;

  setUp(() {
    scans = StreamController<ScanResult>.broadcast();
    cameraInits = StreamController<Object?>.broadcast();
    ringing = StreamController<AlarmSet>.broadcast();
    QrScanner.debugScanStreamOverride = scans.stream;
    QrScanner.debugCameraInitStreamOverride = cameraInits.stream;
    QrScanner.debugRingingStreamOverride = ringing.stream;
  });

  tearDown(() async {
    QrScanner.debugScanStreamOverride = null;
    QrScanner.debugCameraInitStreamOverride = null;
    QrScanner.debugRingingStreamOverride = null;
    QrScanner.debugOnAlarmHandledOverride = null;
    await scans.close();
    await cameraInits.close();
    await ringing.close();
  });

  group('T-215: once offered, the emergency stop stays until swiped away', () {
    testWidgets(
        'a successful camera re-initialisation after the proof-of-life '
        'timeout does not withdraw it', (tester) async {
      await _pumpScanner(tester);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text(_label), findsOneWidget);

      // What ReaderWidget does after every app resume and camera toggle.
      cameraInits.add(null);
      await tester.pumpAndSettle();

      expect(find.text(_label), findsOneWidget,
          reason: 'the camera reporting success says nothing about whether '
              'it can see anything - the timeout already showed it cannot');
    });

    testWidgets(
        'a successful re-initialisation after a camera error does not '
        'withdraw it', (tester) async {
      await _pumpScanner(tester);
      cameraInits.add(StateError('camera busy'));
      await tester.pumpAndSettle();
      expect(find.text(_label), findsOneWidget,
          reason: 'a camera error offers it immediately');

      cameraInits.add(null);
      await tester.pumpAndSettle();
      expect(find.text(_label), findsOneWidget);
    });

    testWidgets('swiping it away hides it', (tester) async {
      await _pumpScanner(tester, alarmId: 1);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      await _swipeAway(tester);

      expect(find.text(_label), findsNothing);
      expect(find.byType(QrScanner), findsOneWidget,
          reason: 'swiping hides the offer; it stops nothing and closes '
              'nothing');
    });

    testWidgets('after a swipe, a new camera error offers it again',
        (tester) async {
      await _pumpScanner(tester);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await _swipeAway(tester);

      cameraInits.add(null);
      await tester.pumpAndSettle();
      expect(find.text(_label), findsNothing,
          reason: 'counter-test: a successful re-initialisation is no new '
              'failure and must not undo the user\'s own swipe');

      cameraInits.add(StateError('camera lost'));
      await tester.pumpAndSettle();
      expect(find.text(_label), findsOneWidget);
    });

    testWidgets(
        'after a swipe, another stretch without a valid code offers it again',
        (tester) async {
      await _pumpScanner(tester);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await _swipeAway(tester);

      // Scanning keeps "working" (wrong codes), but the right one never comes.
      scans.add(const ScanResult('wrong'));
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(find.text(_label), findsNothing,
          reason: 'counter-test: not straight back - the user just said '
              '"let me try scanning again"');

      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text(_label), findsOneWidget,
          reason: 'the escape hatch must never stay gone for the rest of '
              'the ring just because it was swiped away once');
    });

    testWidgets('counter-test: a successful camera start alone never offers it',
        (tester) async {
      await _pumpScanner(tester);
      cameraInits.add(null);
      scans.add(const ScanResult('wrong'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      expect(find.text(_label), findsNothing);
    });

    testWidgets(
        'counter-test: the import flow keeps its Cancel button and never '
        'shows the emergency stop', (tester) async {
      await _pumpScanner(tester, displayExitButton: true);
      cameraInits.add(StateError('camera busy'));
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text(_label), findsNothing);
    });
  });

  group('T-216: the emergency stop stops only the ringing alarm', () {
    testWidgets(
        'a future manual alarm stays armed; the ringing one is stopped and '
        'handled once', (tester) async {
      final fake = FakeAlarmPlatform();
      final now = DateTime.now();
      final handled = <int>[];
      QrScanner.debugOnAlarmHandledOverride = (appState, id) => handled.add(id);

      await _pumpScanner(tester, alarmId: 1, prepare: (appState) {
        fake.attach(appState);
        appState.manualAlarms.addAll([_manual(1), _manual(2)]);
        fake.armed[1] = _settings(1, now);
        fake.armed[2] = _settings(2, now.add(const Duration(hours: 5)));
        fake.ringing.add(1);
      });
      ringing.add(AlarmSet([_settings(1, now)]));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_label));
      await tester.pumpAndSettle();
      // The platform reports the ring gone, as Alarm.stop does for real.
      ringing.add(AlarmSet.empty());
      await tester.pumpAndSettle();

      expect(fake.stopIds, [1], reason: 'only the ringing alarm is stopped');
      expect(fake.armed.containsKey(2), isTrue,
          reason: 'the next manual alarm must still ring');
      expect(handled, [1],
          reason: 'handled exactly once (T-147), even though RingingWatch '
              'sees the same stop');
      expect(find.byType(QrScanner), findsNothing);
    });

    testWidgets(
        'a repeating manual alarm stopped by emergency is re-armed for its '
        'next occurrence', (tester) async {
      final fake = FakeAlarmPlatform();
      final now = DateTime.now();
      QrScanner.debugOnAlarmHandledOverride = (appState, id) =>
          Handler.onAlarmHandled(appState, id,
              notifications: _SilentNotifications());

      await _pumpScanner(tester, alarmId: 1, prepare: (appState) {
        fake.attach(appState);
        appState.manualAlarms.add(_manual(1,
            repeatOnDays: {for (final d in DayOfWeek.values) d: true}));
        fake.armed[1] = _settings(1, now);
        fake.ringing.add(1);
      });
      ringing.add(AlarmSet([_settings(1, now)]));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_label));
      await tester.pumpAndSettle();
      ringing.add(AlarmSet.empty());
      await tester.pumpAndSettle();

      expect(fake.stopIds, [1]);
      expect(fake.setIds, [1],
          reason: 'the same re-arm a normal dismiss gets (T-14) - and only '
              'once');
      expect(fake.armed[1]!.dateTime.isAfter(now), isTrue,
          reason: 're-armed for its next occurrence, not the one that rang');
    });

    testWidgets(
        'with no alarm id, only alarms that are ringing right now are '
        'stopped', (tester) async {
      final fake = FakeAlarmPlatform();
      final now = DateTime.now();
      final handled = <int>[];
      QrScanner.debugOnAlarmHandledOverride = (appState, id) => handled.add(id);

      await _pumpScanner(tester, prepare: (appState) {
        fake.attach(appState);
        fake.armed[1] = _settings(1, now);
        fake.armed[2] = _settings(2, now.add(const Duration(hours: 5)));
        fake.ringing.add(1);
      });
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_label));
      await tester.pumpAndSettle();

      expect(fake.stopIds, [1]);
      expect(fake.armed.containsKey(2), isTrue);
      expect(handled, [1]);
    });

    testWidgets('with no alarm id and nothing ringing, nothing is stopped',
        (tester) async {
      final fake = FakeAlarmPlatform();
      final now = DateTime.now();

      await _pumpScanner(tester, prepare: (appState) {
        fake.attach(appState);
        fake.armed[2] = _settings(2, now.add(const Duration(hours: 5)));
      });
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_label));
      await tester.pumpAndSettle();

      expect(fake.stopIds, isEmpty);
      expect(fake.armed.containsKey(2), isTrue);
      expect(find.byType(QrScanner), findsNothing,
          reason: 'the user still gets out of the screen');
    });

    // docs/TODO.md T-216 review: `Alarm.stop` reports a failure as `false`,
    // not as an exception - the stop must be checked, not assumed.
    Future<FakeAlarmPlatform> pumpWithFailingStop(WidgetTester tester,
        {required bool stopAllWorks, required List<int> handled}) async {
      final fake = FakeAlarmPlatform();
      final now = DateTime.now();
      QrScanner.debugOnAlarmHandledOverride = (appState, id) => handled.add(id);
      await _pumpScanner(tester, alarmId: 1, prepare: (appState) {
        fake.attach(appState);
        appState.manualAlarms.addAll([
          _manual(1, repeatOnDays: {for (final d in DayOfWeek.values) d: true}),
          _manual(2),
        ]);
        fake.armed[1] = _settings(1, now);
        fake.armed[2] = _settings(2, now.add(const Duration(hours: 5)));
        fake.ringing.add(1);
        // The plugin returned false: nothing changed, it keeps ringing.
        appState.debugPlatformStop = (id) async => fake.stopIds.add(id);
        if (!stopAllWorks) {
          appState.debugPlatformStopAll = () async => fake.stopAllCalls++;
        }
      });
      ringing.add(AlarmSet([_settings(1, now)]));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_label));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets(
        'a stop that silently fails keeps the screen and the button, and '
        'handles nothing', (tester) async {
      final handled = <int>[];
      final fake = await pumpWithFailingStop(tester,
          stopAllWorks: false, handled: handled);

      expect(fake.ringing, contains(1));
      expect(fake.stopAllCalls, 1,
          reason: 'stopping everything is the last resort before giving up');
      expect(find.byType(QrScanner), findsOneWidget,
          reason: 'closing would leave a ringing alarm with no screen and no '
              'button to stop it');
      expect(find.text(_label), findsOneWidget);
      expect(handled, isEmpty,
          reason: 'an alarm that still rings is not handled - nor re-armed');
      expect(fake.setIds, isEmpty);
    });

    testWidgets(
        'when the single stop fails, stopping everything is the fallback; '
        'then the alarm is handled and the screen closes', (tester) async {
      final handled = <int>[];
      final fake = await pumpWithFailingStop(tester,
          stopAllWorks: true, handled: handled);
      ringing.add(AlarmSet.empty());
      await tester.pumpAndSettle();

      expect(fake.stopAllCalls, 1);
      expect(fake.ringing, isEmpty);
      expect(handled, [1]);
      expect(find.byType(QrScanner), findsNothing);
    });

    testWidgets('counter-test: a stop that works never stops everything',
        (tester) async {
      final fake = FakeAlarmPlatform();
      final now = DateTime.now();
      QrScanner.debugOnAlarmHandledOverride = (appState, id) {};
      await _pumpScanner(tester, alarmId: 1, prepare: (appState) {
        fake.attach(appState);
        fake.armed[1] = _settings(1, now);
        fake.armed[2] = _settings(2, now.add(const Duration(hours: 5)));
        fake.ringing.add(1);
      });
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_label));
      await tester.pumpAndSettle();

      expect(fake.stopAllCalls, 0);
      expect(fake.armed.containsKey(2), isTrue);
    });
  });
}
