import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/models/scan_code/scan_result.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';

// docs/TODO.md T-33: the QR gate moved off `mobile_scanner`, which links
// Google's proprietary ML Kit binaries and therefore cannot travel inside a
// GPLv3 APK, onto flutter_zxing (MIT, zxing-cpp under Apache-2.0).
//
// The migration introduced [ScanResult] so that nothing outside
// lib/screens/scan_code/ names a scanner package's types any more - that is
// what makes these tests possible at all, and what would make the next swap
// cheap.
//
// docs/TODO.md T-08 also applies: the gate had no negative test outside the
// E2E suite. It has one now - "a wrong code does not open the gate" is the
// assertion the whole "guaranteed wake-up" promise rests on.

/// Pushes the scanner as a ROUTE, not as the home widget: whether the gate
/// opens is observable only as "did this route pop". A scanner that is the
/// home widget can never disappear, and an assertion against it would be
/// vacuous - which the first version of the negative test below was, as a
/// mutation (make `isDeactivationCodeValid` return true always) proved by
/// staying green.
Future<AppState> _pumpScanner(WidgetTester tester,
    {DeactivationCode? storedCode}) async {
  final appState = AppState();
  await appState.initialized;
  if (storedCode != null) appState.deactivationCode = storedCode;

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
  await tester.pumpAndSettle();
  expect(find.byType(QrScanner), findsOneWidget);
  return appState;
}

/// How often the gate has recorded an accepted scan.
int _acceptedScans() => Diag.records
    .where((r) =>
        r.event == DiagEvent.qrGate &&
        r.fields[DiagField.qrOutcome] == QrOutcome.accepted.code)
    .length;

void main() {
  late StreamController<ScanResult> scans;

  setUp(() async {
    scans = StreamController<ScanResult>.broadcast();
    QrScanner.debugScanStreamOverride = scans.stream;
    // Before Diag.init: the logger persists through SharedPreferences, so the
    // mock store has to exist first.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferences.resetStatic();
    Diag.resetForTest();
    await Diag.init(enabled: true);
  });

  tearDown(() async {
    QrScanner.debugScanStreamOverride = null;
    await scans.close();
  });

  testWidgets('with no code stored, the first scan is imported',
      (tester) async {
    final appState = await _pumpScanner(tester);
    expect(appState.deactivationCode, isNull);

    scans.add(const ScanResult('the-code'));
    await tester.pump();

    expect(appState.deactivationCode?.payload, 'the-code',
        reason: 'the screen doubles as the way to teach the app a code');
  });

  testWidgets('a wrong code does not replace the stored one', (tester) async {
    // The negative case the gate exists for. If a scanned code could overwrite
    // the stored one, the "guaranteed wake-up" would be defeated by printing
    // any QR code at all.
    final appState = await _pumpScanner(tester,
        storedCode: DeactivationCode(payload: 'right'));

    scans.add(const ScanResult('wrong'));
    await tester.pumpAndSettle();

    // The oracle is the diagnostics log, not "did the screen close". Closing
    // also depends on the alarm plugin, which has no channel in a unit test,
    // so a screen that stays put proves nothing - a mutation making the gate
    // accept everything still left it open. `Diag.qrGate(accepted)` is
    // recorded the moment the gate decides, before anything is stopped.
    expect(_acceptedScans(), 0,
        reason: 'the gate must not accept a code that does not match - this '
            'single assertion is the whole "guaranteed wake-up" promise');
    expect(find.byType(QrScanner), findsOneWidget,
        reason: 'and it must not close either');
    expect(appState.deactivationCode?.payload, 'right',
        reason: 'nor may the stored code be overwritten');
  });

  testWidgets('the matching code is accepted', (tester) async {
    // Counter-test against over-correction: a gate that refuses everything
    // would satisfy the test above and lock the user out of their own alarm.
    await _pumpScanner(tester, storedCode: DeactivationCode(payload: 'right'));

    scans.add(const ScanResult('right'));
    await tester.pumpAndSettle();

    expect(_acceptedScans(), 1);
  });

  testWidgets('importing a code closes the screen', (tester) async {
    // Found by an independent review: the import screen left the camera
    // running after the import, so the SAME code decoded again about a second
    // later - and that second decode took the "nothing was said about which
    // alarm rings, so stop them all" path. Closing as soon as the code is
    // learned removes the whole sequence. The screen's job is done at that
    // point: this branch is only reachable from PageImportQr, because a
    // ringing alarm only ever opens the scanner when a code is already set.
    await _pumpScanner(tester);

    scans.add(const ScanResult('the-code'));
    await tester.pumpAndSettle();

    expect(find.byType(QrScanner), findsNothing);
  });

  testWidgets('an empty payload is not imported as a code', (tester) async {
    // `ScanResult('')` is not null, so the null guard let it through and the
    // user ended up with a deactivation code nobody can ever reproduce - the
    // gate would then be unopenable.
    final appState = await _pumpScanner(tester);

    scans.add(const ScanResult(''));
    await tester.pumpAndSettle();

    expect(appState.deactivationCode, isNull);
    expect(find.byType(QrScanner), findsOneWidget,
        reason: 'and nothing was learned, so the screen stays open');
  });

  testWidgets('a scanner that never decodes offers a way out', (tester) async {
    // The lock-in half of the "guaranteed wake-up" promise. An independent
    // review listed six ways the camera can be dead while the library's
    // creation callback reports success or says nothing at all - an empty
    // camera list, a throwing image stream, a controller replaced mid-init, a
    // re-entrant init, a dead decode isolate, an unscannable frame format.
    // Behind `PopScope(canPop: false)` that is a user who cannot stop their
    // alarm.
    await _pumpScanner(tester, storedCode: DeactivationCode(payload: 'right'));

    expect(find.text('Stop alarm'), findsNothing,
        reason: 'not offered while the scanner may still be starting');

    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();

    expect(find.text('Stop alarm'), findsOneWidget,
        reason: 'nothing has been decoded, so the user gets an escape hatch '
            'whatever the camera callbacks claimed');
  });

  testWidgets('a working scanner does not offer the escape hatch',
      (tester) async {
    // Counter-test: the button must not appear just because the user is slow
    // to hold the code up. One decode - even a wrong code - proves the loop
    // runs.
    await _pumpScanner(tester, storedCode: DeactivationCode(payload: 'right'));

    scans.add(const ScanResult('wrong'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();

    expect(find.text('Stop alarm'), findsNothing);
  });

  testWidgets('an empty scan changes nothing', (tester) async {
    // A decode that yields no text must not be treated as an import of "null",
    // which would leave a code nobody can ever reproduce.
    final appState = await _pumpScanner(tester);

    scans.add(const ScanResult(null));
    await tester.pump();

    expect(appState.deactivationCode, isNull);
  });
}
