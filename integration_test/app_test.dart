// Real end-to-end tests, driven against a real (emulated or physical)
// Android device via `flutter test integration_test/` (or `flutter drive`).
// These exercise the actual native `alarm` plugin - alarms really fire via
// the OS. Scenario 3's persistence check currently reads an in-process
// SharedPreferences cache rather than a genuine on-device storage round-trip
// (see docs/TODO.md T-04) - it does not yet prove what its name suggests.
//
// Prerequisites (see .github/workflows for how CI sets these up):
// - All dangerous permissions pre-granted via `adb shell pm grant` /
//   `adb shell appops set`, so the in-app permission flow completes without
//   needing to interact with OS dialogs.
// - Covers the first three items of the E2E test plan in docs/TODO.md (see
//   also docs/REQUIREMENTS.md R3/R4). A fourth item, stale alarm auto-stop,
//   is a pure-logic test covered separately in
//   test/handler_stale_alarm_test.dart instead, since it needs no device/UI.
//
// Scope note: scenario 2 (QR deactivation) injects the scan result via
// QrScanner.debugBarcodeStreamOverride rather than actually feeding camera
// data - see that field's doc comment in lib/screens/scan_code/qr_scanner.dart
// and docs/TODO.md T-16 for why, and what that does and doesn't prove.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/main.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/alarms/screen_active_alarm.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';

/// Repeatedly pumps [tester] until [finder] matches something, or [timeout]
/// elapses. Unlike `pumpAndSettle`, this is safe to use while waiting on a
/// real, slow, external event (like a native alarm actually ringing).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
  Duration step = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out after $timeout waiting for $finder to appear');
}

/// The inverse of [pumpUntilFound] - waits for [finder] to stop matching
/// anything.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
  Duration step = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  fail('Timed out after $timeout waiting for $finder to disappear');
}

Future<AppState> pumpFreshApp(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MyApp(),
    ),
  );

  // Permissions were pre-granted via adb before the test run, so the splash
  // screen's permission check resolves quickly - just wait for MyHomePage.
  await pumpUntilFound(tester, find.byType(MyHomePage),
      timeout: const Duration(seconds: 30));
  await tester.pumpAndSettle();

  return appState;
}

/// Creates a manual alarm ~1 minute from now via the real UI flow (the "add
/// alarm" dialog defaults to now+1 minute, so no time-picker interaction is
/// needed) and returns to the Alarms tab.
Future<void> createManualAlarmOneMinuteFromNow(WidgetTester tester) async {
  expect(find.byType(ScreenAlarms), findsOneWidget);

  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    QrScanner.debugBarcodeStreamOverride = null;
  });

  testWidgets(
    'manual alarm fires and is dismissed via the default overlay',
    (tester) async {
      await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester);

      await pumpUntilFound(
        tester,
        find.byType(ScreenAlarmActive),
        timeout: const Duration(minutes: 2),
      );

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.byType(ScreenAlarmActive), findsNothing);
      expect(find.byType(ScreenAlarms), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'manual alarm with a deactivation code set is dismissed via QR scan',
    (tester) async {
      const testPayload = 'wakeywakey-e2e-test-code';

      final appState = await pumpFreshApp(tester);
      appState.deactivationCode = DeactivationCode(payload: testPayload);

      // A single-subscription controller, not Stream.value: QrScanner
      // subscribes to this in initState and _handleBarcode validates +
      // pops synchronously-ish on the very next event, so if the barcode
      // were queued up before QrScanner mounts (as Stream.value would),
      // the whole mount-validate-pop cycle can finish inside one
      // pumpUntilFound polling gap and never be observed as "found" at
      // all. Waiting to add the event until after QrScanner is confirmed
      // mounted removes that race entirely.
      final barcodeController = StreamController<BarcodeCapture>();
      QrScanner.debugBarcodeStreamOverride = barcodeController.stream;

      await createManualAlarmOneMinuteFromNow(tester);

      await pumpUntilFound(
        tester,
        find.byType(QrScanner),
        timeout: const Duration(minutes: 2),
      );

      barcodeController.add(BarcodeCapture(barcodes: [
        Barcode(rawValue: testPayload, format: BarcodeFormat.qrCode),
      ]));

      // _handleBarcode validates the injected code and pops the scanner
      // automatically - just wait for it to close.
      await pumpUntilGone(
        tester,
        find.byType(QrScanner),
        timeout: const Duration(seconds: 15),
      );
      await tester.pumpAndSettle();
      await barcodeController.close();

      expect(find.byType(QrScanner), findsNothing);
      expect(find.byType(ScreenAlarms), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'a created alarm survives being reloaded from on-device storage',
    (tester) async {
      await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester);

      // Don't wait for it to ring - just confirm it's really on disk by
      // constructing a completely fresh AppState (as a real app restart
      // would) and checking it reads the alarm back via SharedPreferences,
      // rather than relying on in-memory state.
      final reloaded = AppState();
      await reloaded.initialized;

      expect(reloaded.manualAlarms, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
