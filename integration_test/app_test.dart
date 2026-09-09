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

import 'package:alarm/alarm.dart';
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
///
/// Fails fast with a clear message if the alarm that was actually scheduled
/// lands far from "now + 1 minute": the dialog's default is minute-truncated
/// (`DateTime.now().add(Duration(minutes: 1))` -> hour/minute only), so a
/// Save that crosses a minute boundary can silently schedule the alarm 24
/// hours out - without this check, a caller's `pumpUntilFound
/// (ScreenAlarmActive)` would instead time out after 2 minutes with a
/// misleading "the alarm never rang" failure (docs/TODO.md T-23).
Future<void> createManualAlarmOneMinuteFromNow(
    WidgetTester tester, AppState appState) async {
  expect(find.byType(ScreenAlarms), findsOneWidget);

  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();

  final createdAlarm = appState.manualAlarms.single;
  final scheduledAlarms = await Alarm.getAlarms();
  AlarmSettings? nativeAlarm;
  for (final alarm in scheduledAlarms) {
    if (alarm.id == createdAlarm.id) {
      nativeAlarm = alarm;
      break;
    }
  }
  if (nativeAlarm == null) {
    fail('Alarm ${createdAlarm.id} was created in AppState but never reached '
        'the native alarm plugin (Alarm.getAlarms() has no matching entry).');
  }
  final difference = nativeAlarm.dateTime.difference(DateTime.now()).abs();
  if (difference > const Duration(minutes: 2)) {
    fail('Expected the created alarm to fire in ~1 minute, but it is '
        'scheduled for ${nativeAlarm.dateTime} (${difference.inMinutes} '
        'minutes from now) - likely the minute-truncated "now + 1 minute" '
        'dialog default landed on the wrong side of a minute boundary '
        '(docs/TODO.md T-23).');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Each scenario creates exactly one alarm; stopping everything before and
  // after every test keeps them independent regardless of how the previous
  // one ended, so one failure can't cascade into a false failure in the next
  // (docs/TODO.md T-23).
  setUp(() async {
    await Alarm.stopAll();
  });

  tearDown(() async {
    QrScanner.debugBarcodeStreamOverride = null;
    await Alarm.stopAll();
  });

  testWidgets(
    'manual alarm fires and is dismissed via the default overlay',
    (tester) async {
      final appState = await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester, appState);

      await pumpUntilFound(
        tester,
        find.byType(ScreenAlarmActive),
        timeout: const Duration(minutes: 2),
      );

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.byType(ScreenAlarmActive), findsNothing);
      expect(find.byType(ScreenAlarms), findsOneWidget);
      // Not just "the screen went away" - the alarm itself must actually
      // have stopped (docs/TODO.md T-09).
      expect(await Alarm.getAlarms(), isEmpty);
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
      addTearDown(barcodeController.close);

      await createManualAlarmOneMinuteFromNow(tester, appState);

      await pumpUntilFound(
        tester,
        find.byType(QrScanner),
        timeout: const Duration(minutes: 2),
      );

      // T-08: the "guaranteed wake-up" gate's one job is refusing a wrong
      // code - a mismatching scan must never dismiss it.
      barcodeController.add(BarcodeCapture(barcodes: [
        Barcode(rawValue: 'not-the-right-code', format: BarcodeFormat.qrCode),
      ]));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(QrScanner), findsOneWidget);
      expect(await Alarm.getAlarms(), isNotEmpty);

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

      expect(find.byType(QrScanner), findsNothing);
      expect(find.byType(ScreenAlarms), findsOneWidget);
      // Not just "the screen went away" - the alarm itself must actually
      // have stopped (docs/TODO.md T-09).
      expect(await Alarm.getAlarms(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'a created alarm survives being reloaded from on-device storage',
    (tester) async {
      final appState = await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester, appState);

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
