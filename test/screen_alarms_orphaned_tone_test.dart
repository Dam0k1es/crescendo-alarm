import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';

// Independent-review finding on docs/TODO.md T-56: a pre-T-56 install's
// custom tone lived at a fixed path (`custom_tones/custom_tone.<ext>`) that
// this version never writes to again, so upgrading orphans any alarm (or
// AppState.selectedTone itself) that still points at it. The add/edit
// dialog's tone DropdownButton requires its `value` to match exactly one of
// its `items` - an unmatched value throws an assertion in debug builds
// (which includes this test) and would silently render blank in release.

void main() {
  testWidgets(
      'editing an alarm whose stored tone no longer exists does not crash '
      'the dropdown', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;

    // Simulates a pre-T-56 install: a tone path that matches neither a
    // bundled tone nor anything in (the now-empty) AppState.customTones.
    final alarm = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      tone: 'custom_tones/custom_tone.mp3',
      id: 1,
    );
    appState.manualAlarms.add(alarm);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    // Opening the edit dialog builds the DropdownButton with the orphaned
    // tone as its initial value - this is where the assertion would fire.
    // Tapping the ListTile itself (not a bare GestureDetector.last, which
    // also matches Material internals like Switch/TabBar) reaches the
    // list item's own onTap via hit-testing its ancestor.
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the dropdown must fall back to a valid tone, not assert '
            'on an orphaned value');
    expect(find.text('Edit Alarm'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = appState.manualAlarms.single;
    expect(saved.tone, 'assets/sounds/annoying_alarm.mp3',
        reason: 'saving with the orphaned value never re-selected should '
            'persist the fallback, not the dead path');
  });
}
