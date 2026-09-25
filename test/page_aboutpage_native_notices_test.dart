import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/screens/settings/page_aboutpage.dart';

// docs/TODO.md T-142: flutter_zxing compiles third-party C/C++ (zxing-cpp,
// its bundled "librscpp", and zint) into the app at build time -
// Flutter's own licence collector (see page_aboutpage_third_party_licenses_test.dart)
// only reads package-root LICENSE files and never sees this. Kept in its
// own file, matching the precedent already documented in
// page_aboutpage_licenses_test.dart (an isolate-pairing quirk between the
// About page's tests, not a real interaction).

void main() {
  testWidgets(
      'the About page has a way to read the native code licence notices',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PageAboutpage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Native Code Notices'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Apache License'), findsWidgets,
        reason: 'Apache-2.0 §4(a) requires the licence text to travel with '
            'the distribution - a GitHub README is not "with the '
            'distribution" for someone who never leaves the app');
    expect(find.textContaining('Robin Stuart'), findsWidgets,
        reason: 'BSD-3 requires the copyright notice to be retained');
  });
}
