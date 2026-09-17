import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/models/scan_code/scan_result.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';

// The one assertion whose absence let three mutations survive: deleting the
// pop, deleting `Alarm.stop`, and deleting the emergency button all kept the
// gate tests green, because nothing ever observed the gate OPENING.
//
// It lives in a file of its own on purpose. `flutter test` gives each file its
// own isolate, and this test needs `runAsync` plus real platform-channel
// futures from the alarm plugin; run after the other gate tests in the same
// isolate it fails, while it passes alone and in every pairing tried. Rather
// than chase that harness interaction, the test that needs a clean isolate
// gets one - the alternative was to drop the assertion, and that assertion is
// the "guaranteed wake-up" promise's other half.

void main() {
  late StreamController<ScanResult> scans;

  setUp(() {
    scans = StreamController<ScanResult>.broadcast();
    QrScanner.debugScanStreamOverride = scans.stream;
  });

  tearDown(() async {
    QrScanner.debugScanStreamOverride = null;
    await scans.close();
  });

  testWidgets('a matching code closes the screen', (tester) async {
    // The assertion whose absence let three mutations survive: deleting the
    // pop, deleting `Alarm.stop`, and deleting the emergency button all kept
    // the old tests green.
    //
    // Everything up to the scan happens inside `runAsync`, and that is
    // load-bearing. The scan subscription is created in `initState`, so its
    // callbacks run in whatever zone was active THEN - and in a widget test's
    // default fake-async zone the alarm plugin's platform-channel futures
    // never complete. The validation would stall forever on `getAlarms`, and
    // everything after it - including the pop - would simply never run. That
    // is a property of the harness, not of the app.
    await tester.runAsync(() async {
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
                  MaterialPageRoute<void>(builder: (_) => const QrScanner()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QrScanner), findsOneWidget);

      scans.add(const ScanResult('right'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    // Outside runAsync again: the pop has fired, its route animation has not.
    await tester.pumpAndSettle();

    expect(find.byType(QrScanner), findsNothing,
        reason: 'the gate opened, so the user is let out');
  });
}
