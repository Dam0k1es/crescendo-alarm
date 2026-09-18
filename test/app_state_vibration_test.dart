import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';

// docs/TODO.md T-50: there was no vibration setting anywhere in the app at
// all before this - every alarm always vibrated (buildRingingAlarmSettings'
// vibrate parameter was hardcoded `true`), regardless of anything the user
// could do. AppState.vibrationEnabled is the global default new alarms
// inherit, mirroring selectedVolume/selectedTone/gentleWakeUpEnabled.

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('defaults to true, matching the previously hardcoded behaviour',
      () async {
    final appState = await _fresh();
    expect(appState.vibrationEnabled, isTrue);
  });

  test('persists across a restart', () async {
    final first = await _fresh();
    first.vibrationEnabled = false;

    final second = AppState();
    await second.initialized;
    expect(second.vibrationEnabled, isFalse);
  });

  test('notifies listeners', () async {
    final appState = await _fresh();
    var notified = false;
    appState.addListener(() => notified = true);

    appState.vibrationEnabled = false;

    expect(notified, isTrue);
  });
}
