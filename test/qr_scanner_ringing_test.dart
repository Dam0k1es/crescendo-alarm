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
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/models/scan_code/scan_result.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';

// Same bug and fix as test/screen_alarm_active_ringing_test.dart, for the
// other screen a ringing alarm can open: QrScanner, shown instead of
// ScreenAlarmActive whenever a deactivation code is set. Only relevant when
// `alarmId` is non-null - a plain code-import scan (alarmId == null) has
// nothing ringing to watch, and must not be affected.

AlarmSettings _fakeAlarmSettings(int id) => AlarmSettings(
      id: id,
      dateTime: DateTime.now(),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(title: 't', body: 'b'),
    );

Future<AppState> _pumpScanner(WidgetTester tester, {int? alarmId}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  appState.deactivationCode = DeactivationCode(payload: 'right');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QrScanner(alarmId: alarmId),
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

void main() {
  late StreamController<AlarmSet> ringing;
  late StreamController<ScanResult> scans;

  setUp(() {
    ringing = StreamController<AlarmSet>.broadcast();
    QrScanner.debugRingingStreamOverride = ringing.stream;
    // Not exercised by these tests, but without it the real (camera-backed)
    // ReaderWidget would be built instead, which has no platform channel in
    // `flutter test` and hangs pumpAndSettle indefinitely.
    scans = StreamController<ScanResult>.broadcast();
    QrScanner.debugScanStreamOverride = scans.stream;
  });

  tearDown(() async {
    QrScanner.debugRingingStreamOverride = null;
    QrScanner.debugScanStreamOverride = null;
    await ringing.close();
    await scans.close();
  });

  testWidgets(
      'closes itself once its ringing alarm disappears from the ringing set',
      (tester) async {
    await _pumpScanner(tester, alarmId: 1);

    ringing.add(AlarmSet([_fakeAlarmSettings(1)]));
    await tester.pumpAndSettle();
    expect(find.byType(QrScanner), findsOneWidget,
        reason: 'still ringing - the guaranteed wake-up gate must stay up');

    ringing.add(AlarmSet.empty());
    await tester.pumpAndSettle();
    expect(find.byType(QrScanner), findsNothing,
        reason: 'the alarm was stopped elsewhere (e.g. notification swipe) - '
            'the scanner must not get stuck');
  });

  testWidgets('a plain code-import scan (no alarmId) is unaffected',
      (tester) async {
    await _pumpScanner(tester, alarmId: null);

    ringing.add(AlarmSet.empty());
    await tester.pumpAndSettle();

    expect(find.byType(QrScanner), findsOneWidget,
        reason: 'nothing is ringing for this screen to watch');
  });

  testWidgets('the very first (seed-like) event does not auto-close',
      (tester) async {
    await _pumpScanner(tester, alarmId: 1);

    ringing.add(AlarmSet.empty());
    await tester.pumpAndSettle();

    expect(find.byType(QrScanner), findsOneWidget);
  });
}
