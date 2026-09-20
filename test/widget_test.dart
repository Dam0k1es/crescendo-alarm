import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/main.dart';

void main() {
  testWidgets('App builds and shows the splash screen on first launch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MyApp(),
      ),
    );
    // Not pumpAndSettle: the splash screen's rotation AnimationController
    // repeats forever from the moment initState runs, regardless of which
    // of its two screens is currently built - "no more frames scheduled"
    // never becomes true while it's mounted.
    await tester.pump();
    await tester.pump();

    // docs/TODO.md T-41: the privacy policy is the actual first-run screen
    // now, shown before anything is requested - see
    // test/privacy_before_permissions_test.dart for that behaviour in
    // detail. Acknowledging it is what starts the (deferred, lazy - T-157)
    // permission flow, which on the test host platform resolves within the
    // same pump (no real platform call is made), straight into MyHomePage -
    // too fast to observe an intermediate "Checking permissions..." frame
    // reliably, so this only checks that the privacy gate is gone.
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Continue'), findsNothing);
  });
}
