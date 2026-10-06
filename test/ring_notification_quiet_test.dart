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

import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/models/scan_code/scan_result.dart';
import 'package:crescendo_alarm/screens/alarms/screen_active_alarm.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';
import 'package:crescendo_alarm/utils/ring_notification.dart';

// docs/TODO.md T-229 (maintainer, 2026-10-06): "Die Benachrichtigung ist
// nicht stumm. Ich will nicht, dass sie beim Wecker Bildschirm in den Alarm
// reinragt." - "In der Benachrichtigungsleiste. Der Wecker-Ton soll
// natürlich weiter laufen."
//
// Both ring screens ask the native side to quiet the plugin's ringing
// notification when they appear and every time the app comes back to the
// foreground while they are showing. Whether it is actually quieted (app in
// the foreground, device not locked, notification still the plugin's) is
// decided natively - RingNotificationPolicy, JVM-tested.

Future<void> _open(WidgetTester tester, AppState appState, Widget screen) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => screen)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Not pumpAndSettle: ScreenAlarmActive's clock Timer.periodic never ends.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _cycleLifecycle(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  late List<int> quieted;
  late StreamController<AlarmSet> ringing;
  late StreamController<ScanResult> scans;
  late AppState appState;

  setUp(() async {
    quieted = [];
    quietRingNotification = (alarmId) async => quieted.add(alarmId);
    ringing = StreamController<AlarmSet>.broadcast();
    scans = StreamController<ScanResult>.broadcast();
    ScreenAlarmActive.debugRingingStreamOverride = ringing.stream;
    QrScanner.debugRingingStreamOverride = ringing.stream;
    QrScanner.debugScanStreamOverride = scans.stream;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    appState = AppState();
    await appState.initialized;
  });

  tearDown(() async {
    quietRingNotification = defaultQuietRingNotification;
    ScreenAlarmActive.debugRingingStreamOverride = null;
    QrScanner.debugRingingStreamOverride = null;
    QrScanner.debugScanStreamOverride = null;
    await ringing.close();
    await scans.close();
  });

  testWidgets(
      'the plain ring screen quiets its own alarm\'s notification once when '
      'shown, and again whenever the app returns to the foreground',
      (tester) async {
    await _open(tester, appState, const ScreenAlarmActive(alarmId: 7));
    expect(quieted, [7], reason: 'exactly once on appearing');

    await tester.pump(const Duration(seconds: 30));
    expect(quieted, [7], reason: 'no repeated calls while nothing changes');

    // The heads-up over an unlocked phone in another app is how the user
    // finds the alarm, so the native side leaves it alone while the app is
    // in the background - the next resume (tapping it) quiets it then.
    await _cycleLifecycle(tester);
    expect(quieted, [7, 7]);
  });

  testWidgets('the QR gate ring screen quiets its alarm\'s notification too',
      (tester) async {
    appState.deactivationCode = DeactivationCode(payload: 'right');
    await _open(tester, appState, const QrScanner(alarmId: 9));
    expect(quieted, [9]);
    await _cycleLifecycle(tester);
    expect(quieted, [9, 9]);
  });

  testWidgets('a plain code-import scan (nothing ringing) never touches a '
      'notification', (tester) async {
    await _open(tester, appState, const QrScanner());
    await _cycleLifecycle(tester);
    expect(quieted, isEmpty);
  });

  testWidgets('once the ring screen is gone, a resume quiets nothing',
      (tester) async {
    await _open(tester, appState, const ScreenAlarmActive(alarmId: 7));
    await tester.pumpWidget(const SizedBox());
    await _cycleLifecycle(tester);
    expect(quieted, [7]);
  });

  test('without a native side (flutter test, Linux) the call fails quietly',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await expectLater(defaultQuietRingNotification(1), completes);
  });
}
