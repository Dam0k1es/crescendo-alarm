import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/screens/settings/page_aboutpage.dart';

// docs/TODO.md T-36: Flutter embeds every dependency's licence in the
// binary, but nothing in the app ever displayed them - so the BSD/MIT/
// Apache notice-retention obligations, and GPLv3's own requirement to make
// the licence available to the user, were not actually met in the shipped
// product. `grep -rn "showLicensePage\|LicensePage\|NOTICES" lib/` used to
// return 0 hits.
//
// This file checks the app's OWN GPLv3 licence is readable (not just
// referenced from a README a user never sees). The third-party-notices half
// lives in its own file, test/page_aboutpage_third_party_licenses_test.dart
// - the same split as qr_scanner_gate_test.dart/qr_scanner_close_test.dart:
// `flutter test` gives each file its own isolate, and the two tests fail
// paired in one but pass alone and in every other pairing tried.

void main() {
  testWidgets('the About page has a way to read the GPLv3 licence text',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PageAboutpage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('License'));
    await tester.pumpAndSettle();

    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsWidgets,
        reason: 'a link to a README on GitHub is not "available to the '
            'user" for someone who never leaves the app');
  });
}
