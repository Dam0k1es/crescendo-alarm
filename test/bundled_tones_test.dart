import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/bundled_tones.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';
import 'package:wakeywakey/screens/settings/page_alarmtones.dart';

// docs/TODO.md T-167: the bundled tones' display names used to be
// hardcoded twice - once in screen_alarms.dart's add/edit dialog dropdown,
// once in page_alarmtones.dart's own tone list - and two of the six ("Wakey
// Wakey", "WakeyWakey 2") were named after the app itself rather than what
// the sound actually is (maintainer feedback). Both screens now read from
// the single `bundledTones` list in lib/models/alarms/bundled_tones.dart;
// this guards that both actually render its current names, not a leftover
// hardcoded copy that would otherwise silently keep showing the old ones.

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('the shared list itself no longer names a tone after the app', () {
    // The concrete regression the maintainer reported.
    final names = bundledTones.map((t) => t.$1).toList();
    expect(names, isNot(contains('WakeyWakey')));
    expect(names, isNot(contains('WakeyWakey 2')));
    expect(names.toSet().length, names.length,
        reason: 'no two bundled tones should share a display name');
  });

  testWidgets('Settings > Alarm Tones renders every bundled tone\'s current name',
      (tester) async {
    final appState = await _freshAppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: PageAlarmTones()),
      ),
    );
    await tester.pumpAndSettle();

    for (final (name, _) in bundledTones) {
      expect(find.text(name), findsOneWidget,
          reason: 'bundled tone "$name" is missing from Settings > Alarm '
              'Tones');
    }
    expect(find.text('WakeyWakey'), findsNothing);
    expect(find.text('WakeyWakey 2'), findsNothing);
  });

  testWidgets(
      'the manual-alarm dialog\'s tone dropdown offers every bundled '
      'tone\'s current name', (tester) async {
    final appState = await _freshAppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Opens the dropdown menu overlay - only then are the non-selected
    // items' labels actually in the widget tree. The dialog scrolls, so the
    // dropdown can exist below the default 600px test viewport.
    final dropdown = find.byType(DropdownButton<String>);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    for (final (name, _) in bundledTones) {
      expect(find.text(name), findsWidgets,
          reason: 'bundled tone "$name" is missing from the tone dropdown');
    }
    expect(find.text('WakeyWakey'), findsNothing);
    expect(find.text('WakeyWakey 2'), findsNothing);
  });
}
