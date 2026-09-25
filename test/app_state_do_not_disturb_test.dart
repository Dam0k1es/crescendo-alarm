import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';

// docs/TODO.md T-184 (maintainer request): AppState.doNotDisturbEnabled is
// the master toggle - off by default (a new, silent-by-default behavior
// change to the device's notifications is not something to turn on for
// everyone unasked, matching this project's general "off by default" bias
// for anything with a real side effect - see the diagnostics toggle, T-174).

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('defaults to off', () async {
    final appState = await _fresh();
    expect(appState.doNotDisturbEnabled, isFalse);
  });

  test('persists across a restart', () async {
    final first = await _fresh();
    first.doNotDisturbEnabled = true;

    final second = AppState();
    await second.initialized;
    expect(second.doNotDisturbEnabled, isTrue);
  });

  test('notifies listeners', () async {
    final appState = await _fresh();
    var notified = false;
    appState.addListener(() => notified = true);

    appState.doNotDisturbEnabled = true;

    expect(notified, isTrue);
  });
}
