import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/scan_code/page_deactivation_code.dart';

// docs/REQUIREMENTS.md R13: "Import" already accepted any pre-existing QR
// code, verbatim - but nothing on screen said so, so it read like it only
// accepted something WakeyWakey itself had generated and exported. This
// pins down the hint that makes the existing capability discoverable.
void main() {
  testWidgets(
      'the no-code screen explains that Import accepts any pre-existing QR code',
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

    expect(
        find.textContaining(
            'Import works with any QR code you already have'),
        findsOneWidget);
  });
}
