import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/screens/settings/page_aboutpage.dart';

// docs/TODO.md T-36, second half - see page_aboutpage_licenses_test.dart for
// why this lives in its own file (an isolate-pairing quirk, not a real
// interaction, matching the precedent already documented in
// qr_scanner_gate_test.dart/qr_scanner_close_test.dart).

void main() {
  testWidgets(
      'the About page has a way to reach the third-party notices Flutter '
      'already collects', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PageAboutpage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Third-Party Licenses'));
    // Not pumpAndSettle: LicensePage's own progress indicator animates
    // indefinitely while it enumerates every bundled package's licence
    // text, which settle would then wait on forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LicensePage), findsOneWidget,
        reason: 'Flutter\'s own collected dependency notices must actually '
            'be reachable, not merely present in the binary');
  });
}
