import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/settings/page_appearance.dart';

// docs/TODO.md T-51: a new "Follow System Theme" option, which - per the
// maintainer's own spec - greys out the manual Dark Mode switch while it is
// on rather than just leaving it there to silently do nothing.

Future<AppState> _pumpAppearance(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: PageAppearance()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

Switch _switchFor(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key));

void main() {
  testWidgets('the dark mode switch is enabled while not following the '
      'system', (tester) async {
    await _pumpAppearance(tester);

    expect(_switchFor(tester, const Key('darkModeSwitch')).onChanged,
        isNotNull);
  });

  testWidgets(
      'turning on "Follow System Theme" disables (greys out) the dark mode '
      'switch', (tester) async {
    final appState = await _pumpAppearance(tester);

    await tester.tap(find.byKey(const Key('followSystemThemeSwitch')));
    await tester.pumpAndSettle();

    expect(appState.followSystemTheme, isTrue);
    expect(_switchFor(tester, const Key('darkModeSwitch')).onChanged, isNull,
        reason: 'a null onChanged is how Flutter\'s own Switch renders as '
            'greyed out/disabled');
  });

  testWidgets('turning "Follow System Theme" back off re-enables the dark '
      'mode switch', (tester) async {
    final appState = await _pumpAppearance(tester);

    await tester.tap(find.byKey(const Key('followSystemThemeSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('followSystemThemeSwitch')));
    await tester.pumpAndSettle();

    expect(appState.followSystemTheme, isFalse);
    expect(_switchFor(tester, const Key('darkModeSwitch')).onChanged,
        isNotNull);
  });

  testWidgets('the dark mode switch, while disabled, cannot be toggled by '
      'tapping it', (tester) async {
    final appState = await _pumpAppearance(tester);
    appState.followSystemTheme = true;
    await tester.pumpAndSettle();
    final before = appState.darkMode;

    await tester.tap(find.byKey(const Key('darkModeSwitch')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(appState.darkMode, before);
  });
}
