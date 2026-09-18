import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/app_state.dart';

// docs/TODO.md T-45: `_loadFromPreferences`'s own comment promised "a failure
// here must never leave the app unable to start", but `SharedPreferences
// .getInstance()` sat OUTSIDE the try block that promise was about - a
// throwing getInstance() (a platform-channel failure, corrupted storage)
// therefore propagated out of `_loadFromPreferences`, which `initialized`
// exposes and which `main()` awaits before `runApp()`. For an alarm clock
// that means every already-armed platform alarm becomes unreachable: no
// checkpoint runs, no dismiss screen shows, nothing.
//
// `getPrefsInstance` is injected the same way `documentsDirectory`/
// `fetchEvents`/`now` are elsewhere in this class, purely so a throwing
// SharedPreferences plugin can be simulated without a platform channel.

void main() {
  test('a throwing getPrefsInstance does not block app startup', () async {
    final appState = AppState(
      getPrefsInstance: () async =>
          throw Exception('simulated platform channel failure'),
    );

    // The regression: before the fix, this await never completed with an
    // error caught here - it threw straight out of `initialized`, which is
    // exactly what blocked `runApp()` in main().
    await appState.initialized;

    // Degraded to defaults rather than left half-initialized.
    expect(appState.reminderEnabled, isA<bool>());
  });

  test('a throwing getPrefsInstance still lets listeners be notified',
      () async {
    var notified = false;
    final appState = AppState(
      getPrefsInstance: () async => throw Exception('boom'),
    );
    appState.addListener(() => notified = true);

    await appState.initialized;

    expect(notified, isTrue,
        reason:
            'the UI (a ChangeNotifierProvider consumer) must still get a '
            'build even when preferences never loaded');
  });
}
