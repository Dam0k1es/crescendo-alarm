import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/main.dart';

// docs/TODO.md T-41: the privacy policy used to be reachable only through
// Settings, which a user only reaches AFTER the splash screen has already
// requested permissions - the transparency step came after the consent
// step, backwards for a project claiming GDPR alignment. The splash screen
// now shows the privacy policy first and defers requesting any permission
// until the user acknowledges it.
void main() {
  testWidgets(
      'the splash screen shows the privacy policy before requesting any permission',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
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

    expect(find.textContaining('Privacy Policy'), findsWidgets,
        reason:
            'the policy must be shown before anything is requested, not '
            'only reachable later via Settings');
    expect(appState.permissionsGranted, isFalse,
        reason: 'permissions must not be requested (and therefore never '
            'reported as granted) until the policy is acknowledged');

    // The oracle is AppState, not a transient widget: on the test host
    // platform the permission flow itself is a no-op that resolves within
    // the same pump as the tap (no real platform call is made), so the
    // "Checking permissions..." frame in between is not reliably
    // observable - what matters is that acknowledging is what triggers it
    // at all.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();

    expect(appState.permissionsGranted, isTrue,
        reason: 'acknowledging the policy is what starts the (deferred, '
            'lazy - see T-157) permission flow');
  });
}
