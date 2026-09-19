import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/scan_code/page_deactivation_code.dart';

// Real-device report: importing a deactivation code via the QR scanner
// (a separate pushed route, PageImportQr -> QrScanner) closed the camera as
// if it had worked, but the deactivation-code screen underneath kept
// showing "no code configured" - the import had actually succeeded in
// AppState, but this screen had subscribed to it with `listen: false`, so
// nothing outside its own Generate/Remove buttons could ever make it
// rebuild. This mutates AppState the same way the scanner does - directly,
// not through one of this screen's own buttons - to prove the screen
// reacts regardless of which widget made the change.
void main() {
  testWidgets(
      'the screen reflects a deactivation code set by something other than its own buttons',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: PageDeactivationCode()),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Currently no deactivation code configured'),
        findsOneWidget);

    // The mutation QrScanner._handleScan performs on a successful import -
    // note this is NOT going through PageDeactivationCode's own
    // generateCodeButton/removeCodeButton, whose onPressed handlers wrap the
    // same assignment in their own local setState.
    appState.deactivationCode = DeactivationCode(payload: 'scanned-elsewhere');
    await tester.pump();

    expect(find.textContaining('Currently no deactivation code configured'),
        findsNothing,
        reason: 'the screen must pick up a code set by another widget, not '
            'only one set through its own buttons');
    expect(find.byType(QrImageView), findsOneWidget,
        reason: 'the QR image for the newly set code should now render');
  });
}
