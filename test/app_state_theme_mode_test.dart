import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';

// docs/TODO.md T-51: the app could only ever be switched to dark mode by
// hand (`MyApp.build` read `appState.darkMode`, never `ThemeMode.system`) -
// there was no way to have it follow the OS setting automatically.
// `AppState.themeMode` centralises the combination of the two settings into
// one computed value, so main.dart doesn't have to (and can't drift from
// this, the same reasoning as every other "one source of truth" value in
// this project).

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('follows the system by default is off, dark mode off -> light', () async {
    final appState = await _fresh();
    expect(appState.followSystemTheme, isFalse);
    expect(appState.themeMode, ThemeMode.light);
  });

  test('dark mode on, not following the system -> dark', () async {
    final appState = await _fresh();
    appState.darkMode = true;
    expect(appState.themeMode, ThemeMode.dark);
  });

  test('following the system overrides the manual dark-mode value', () async {
    final appState = await _fresh();
    appState.darkMode = true;
    appState.followSystemTheme = true;
    expect(appState.themeMode, ThemeMode.system);
  });

  test('turning "follow system" back off restores the manual value', () async {
    final appState = await _fresh();
    appState.darkMode = true;
    appState.followSystemTheme = true;
    appState.followSystemTheme = false;
    expect(appState.themeMode, ThemeMode.dark,
        reason: 'the manual choice was never lost, only overridden while '
            'following the system');
  });

  test('followSystemTheme persists across a restart', () async {
    final first = await _fresh();
    first.followSystemTheme = true;

    final second = AppState();
    await second.initialized;
    expect(second.followSystemTheme, isTrue);
  });

  test('setting followSystemTheme notifies listeners', () async {
    final appState = await _fresh();
    var notified = false;
    appState.addListener(() => notified = true);

    appState.followSystemTheme = true;

    expect(notified, isTrue);
  });
}
