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

import 'dart:async';

import 'package:alarm/alarm.dart';
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
import 'package:crescendo_alarm/screens/alarms/screen_active_alarm.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';

// docs/TODO.md T-236 (audit G3-03, residual after T-232): the stale rule in
// `Handler.handleAlarm` compares a ring's ORIGINAL due time with now, so a
// ring that is still audibly ringing after more than the 60-minute overdue
// window - which the plugin allows, its loop never ends - was stopped silently
// when the app was opened: no ring screen, no QR gate. Since T-230 (a Recents
// swipe no longer stops the ring) that is reachable on purpose: swipe, wait
// an hour, open the app, and the QR-gated alarm is gone. A ring the platform
// reports as ringing must always get its screen; "stale" only ever applies to
// something that is NOT ringing.
//
// Two harnesses. Most cases use a context that is unmounted right after the
// handler is built: the ring screen can then never be shown, so the number of
// recorded sleeps (the 4 overlay retries plus the final fallback wait) says
// the overlay path was reached, while `isRinging`/`stopAlarm` are spies. That
// proves the decision, not the screen; the mounted-context cases below do.

/// The overdue window (60 minutes, T-217) spelled out, so this file does not
/// depend on the constant it guards (it is pinned by
/// test/direct_boot_fallback_contract_test.dart).
const Duration _window = Duration(minutes: 60);

AlarmSettings _alarmDue(DateTime due, {int id = 1}) => AlarmSettings(
      id: id,
      dateTime: due,
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(
        title: 'Test alarm',
        body: 'ringing',
      ),
    );

class _Spy {
  final List<int> asked = [];
  final List<int> stopped = [];
  final List<Duration> sleeps = [];
}

Future<(Handler, AppState)> _unmountedHandler(
  WidgetTester tester,
  _Spy spy, {
  required bool Function() ringing,
  Future<bool> Function(int id)? stopAlarm,
  bool throwOnRinging = false,
  void Function(AppState)? prepare,
}) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  prepare?.call(appState);
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
  final handler = Handler(
    capturedContext,
    runCheckpoint: (_) async => null,
    sleep: (d) async => spy.sleeps.add(d),
    isRinging: (id) async {
      spy.asked.add(id);
      if (throwOnRinging) throw StateError('platform unreachable');
      return ringing();
    },
    stopAlarm: stopAlarm ??
        (id) async {
          spy.stopped.add(id);
          return true;
        },
  );
  await tester.pumpWidget(const SizedBox());
  return (handler, appState);
}

/// The overlay path was reached: all four retries waited, then the final
/// fallback wait - exactly what test/handler_overlay_retry_test.dart pins.
void _expectOverlayPathReached(_Spy spy, {String? reason}) {
  expect(spy.sleeps, hasLength(Handler.maxOverlayAttempts),
      reason: reason ?? 'the ring screen was attempted');
  expect(spy.sleeps.toSet(), {Handler.overlayRetryDelay});
}

void main() {
  group('a ring the platform reports as ringing is never stopped silently',
      () {
    testWidgets('3 hours after its due time: no stop, the ring screen path',
        (tester) async {
      final spy = _Spy();
      final (handler, _) = await _unmountedHandler(tester, spy,
          ringing: () => true);

      await handler.handleAlarm(
          _alarmDue(DateTime.now().subtract(const Duration(hours: 3))));

      expect(spy.asked, [1], reason: 'the decision asked the platform');
      expect(spy.stopped, isEmpty);
      _expectOverlayPathReached(spy);
    });

    testWidgets('59 and 61 minutes: ringing is never stopped, not ringing is '
        'stopped only past the window', (tester) async {
      for (final minutes in [59, 61]) {
        for (final ringing in [true, false]) {
          final spy = _Spy();
          final (handler, _) = await _unmountedHandler(tester, spy,
              ringing: () => ringing);

          await handler.handleAlarm(_alarmDue(
              DateTime.now().subtract(Duration(minutes: minutes))));

          final reason = '$minutes min, ringing=$ringing';
          if (minutes > _window.inMinutes && !ringing) {
            expect(spy.stopped, [1], reason: reason);
            expect(spy.sleeps, isEmpty, reason: reason);
          } else {
            expect(spy.stopped, isEmpty, reason: reason);
            _expectOverlayPathReached(spy, reason: reason);
          }
        }
      }
    });

    testWidgets('an unreadable ringing state counts as ringing: never '
        'silence an alarm on doubt', (tester) async {
      final spy = _Spy();
      final (handler, _) = await _unmountedHandler(tester, spy,
          ringing: () => true, throwOnRinging: true);

      await handler.handleAlarm(
          _alarmDue(DateTime.now().subtract(const Duration(hours: 3))));

      expect(spy.stopped, isEmpty);
      _expectOverlayPathReached(spy);
    });

    testWidgets('the alarm id is passed through, also for an id AppState has '
        'never seen', (tester) async {
      final spy = _Spy();
      final (handler, appState) = await _unmountedHandler(tester, spy,
          ringing: () => true);
      expect(appState.getAlarm(4242), isNull, reason: 'precondition');

      await handler.handleAlarm(_alarmDue(
          DateTime.now().subtract(const Duration(hours: 3)),
          id: 4242));

      expect(spy.asked, [4242]);
      expect(spy.stopped, isEmpty);
      _expectOverlayPathReached(spy);
    });
  });

  group('a stale event that is NOT ringing keeps its old treatment', () {
    testWidgets('it is stopped and nothing is shown for it', (tester) async {
      final spy = _Spy();
      final (handler, appState) = await _unmountedHandler(tester, spy,
          ringing: () => false);
      final due = DateTime.now().subtract(const Duration(hours: 3));

      await handler.handleAlarm(_alarmDue(due));

      expect(spy.stopped, [1]);
      expect(spy.sleeps, isEmpty);
      expect(appState.snoozeOriginFor(1), isNull,
          reason: 'a silently stopped event records no snooze origin');
    });

    testWidgets('a stop that returns false falls through to the ring screen',
        (tester) async {
      final spy = _Spy();
      final (handler, _) = await _unmountedHandler(tester, spy,
          ringing: () => false, stopAlarm: (id) async {
        spy.stopped.add(id);
        return false;
      });

      await handler.handleAlarm(
          _alarmDue(DateTime.now().subtract(const Duration(hours: 3))));

      expect(spy.stopped, [1]);
      _expectOverlayPathReached(spy,
          reason: 'an alarm that could not be stopped must get a screen');
    });

    testWidgets('a stop that throws falls through to the ring screen too',
        (tester) async {
      final spy = _Spy();
      final (handler, _) = await _unmountedHandler(tester, spy,
          ringing: () => false, stopAlarm: (id) async {
        spy.stopped.add(id);
        throw StateError('stop failed');
      });

      await handler.handleAlarm(
          _alarmDue(DateTime.now().subtract(const Duration(hours: 3))));

      expect(spy.stopped, [1]);
      _expectOverlayPathReached(spy);
    });
  });

  testWidgets('a fresh ring (inside the window) is never stopped, and its '
      'platform state is not even needed', (tester) async {
    for (final ringing in [true, false]) {
      final spy = _Spy();
      final (handler, _) = await _unmountedHandler(tester, spy,
          ringing: () => ringing);

      await handler.handleAlarm(
          _alarmDue(DateTime.now().subtract(const Duration(minutes: 30))));

      expect(spy.stopped, isEmpty, reason: 'ringing=$ringing');
      _expectOverlayPathReached(spy, reason: 'ringing=$ringing');
    }
  });

  testWidgets('a ring that has been going for 3 hours records its ORIGINAL '
      'due time as the snooze origin (FR-20: the budget is measured from '
      'it)', (tester) async {
    final spy = _Spy();
    final (handler, appState) =
        await _unmountedHandler(tester, spy, ringing: () => true);
    final due = DateTime.now().subtract(const Duration(hours: 3));

    await handler.handleAlarm(_alarmDue(due));

    expect(appState.snoozeOriginFor(1), due,
        reason: 'deliberate: a ring this old is already out of snooze '
            'budget - the screen still appears, with Stop');
  });

  group('mounted context: the user really gets the screen', () {
    late StreamController<AlarmSet> ringingStream;

    setUp(() {
      ringingStream = StreamController<AlarmSet>.broadcast();
      ScreenAlarmActive.debugRingingStreamOverride = ringingStream.stream;
    });

    tearDown(() async {
      ScreenAlarmActive.debugRingingStreamOverride = null;
      QrScanner.debugScanStreamOverride = null;
      QrScanner.debugRingingStreamOverride = null;
      await ringingStream.close();
    });

    Future<Handler> mounted(WidgetTester tester, AppState appState, _Spy spy,
        {required bool ringing}) async {
      late BuildContext captured;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appState,
          child: MaterialApp(
            home: Builder(builder: (context) {
              captured = context;
              return const SizedBox();
            }),
          ),
        ),
      );
      return Handler(
        captured,
        runCheckpoint: (_) async => null,
        sleep: (d) async => spy.sleeps.add(d),
        isRinging: (id) async {
          spy.asked.add(id);
          return ringing;
        },
        stopAlarm: (id) async {
          spy.stopped.add(id);
          return true;
        },
      );
    }

    testWidgets('no code configured: a 3-hour ring shows the plain ring '
        'screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState();
      await appState.initialized;
      final spy = _Spy();
      final handler = await mounted(tester, appState, spy, ringing: true);

      await handler.handleAlarm(
          _alarmDue(DateTime.now().subtract(const Duration(hours: 3))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ScreenAlarmActive), findsOneWidget);
      expect(spy.stopped, isEmpty);
      expect(spy.sleeps, isEmpty);
    });

    testWidgets('a code is configured: a 3-hour ring of a scheduled alarm '
        'and of a manual alarm that requires it shows the QR gate; a manual '
        'alarm that opted out shows the plain screen', (tester) async {
      for (final (id, optedOut, gated) in [
        (10, null, true), // unknown to AppState: follows the code
        (11, false, true), // manual, requires the code
        (12, true, false), // manual, opted out (T-176)
      ]) {
        SharedPreferences.setMockInitialValues({});
        final appState = AppState();
        await appState.initialized;
        appState.deactivationCode = DeactivationCode(payload: 'secret-code');
        if (optedOut != null) {
          appState.manualAlarms.add(ManualAlarm(
            time: const TimeOfDay(hour: 7, minute: 0),
            enabled: true,
            gentlewake: false,
            tone: 'assets/sounds/lollipop.mp3',
            id: id,
            requireDeactivationCode: !optedOut,
          ));
        }
        QrScanner.debugScanStreamOverride = const Stream<ScanResult>.empty();
        QrScanner.debugRingingStreamOverride = ringingStream.stream;
        final spy = _Spy();
        final handler = await mounted(tester, appState, spy, ringing: true);

        await handler.handleAlarm(_alarmDue(
            DateTime.now().subtract(const Duration(hours: 3)),
            id: id));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final reason = 'id $id (opted out: $optedOut)';
        expect(find.byType(QrScanner), gated ? findsOneWidget : findsNothing,
            reason: reason);
        expect(find.byType(ScreenAlarmActive),
            gated ? findsNothing : findsOneWidget,
            reason: reason);
        expect(spy.stopped, isEmpty, reason: reason);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
