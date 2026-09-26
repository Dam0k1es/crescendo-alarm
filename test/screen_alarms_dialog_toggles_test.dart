// docs/TODO.md T-176 (maintainer request): three changes to the manual-alarm
// add/edit dialog.
//
// 1. The weekday selector used to be a `Wrap` with a forced break between
//    the five weekdays and the weekend, and oversized chips (40dp diameter,
//    10dp spacing) - on a realistic phone width that wraps into three visual
//    rows instead of the single row the maintainer asked for, and had no
//    title label explaining what it's for. A narrow test viewport is set up
//    below so this is actually exercised the way it would be on a real
//    phone - the default 800-wide test window is wide enough that the old
//    layout would not visibly wrap, masking the bug.
// 2. A per-alarm Snooze on/off toggle, following the exact Card/Row/Switch
//    pattern the existing "Gentle Wake Up" toggle already established.
// 3. A per-alarm "Guaranteed Wake-Up" (the deactivation-code/QR gate)
//    on/off toggle, same pattern.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';

Future<AppState> _openAddDialog(WidgetTester tester) async {
  // A realistic narrow phone width - see this file's header comment on why
  // the default test viewport would hide the "3 rows" bug entirely.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

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
  return appState;
}

void main() {
  group('weekday selector layout', () {
    testWidgets('shows a small title above the day selector',
        (tester) async {
      await _openAddDialog(tester);
      expect(find.text('Repeat on'), findsOneWidget);
    });

    testWidgets('all seven days render on one visible row, not wrapped',
        (tester) async {
      await _openAddDialog(tester);

      final labels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
      final centers = [
        for (final label in labels) tester.getCenter(find.text(label))
      ];
      final rowY = centers.first.dy;
      for (var i = 0; i < labels.length; i++) {
        expect(centers[i].dy, closeTo(rowY, 0.5),
            reason:
                '"${labels[i]}" must sit on the same row as the others - a '
                'wrapped layout would place at least one of them lower');
      }
      // Also genuinely visible, not just mathematically level - no overflow
      // error was thrown while laying this out.
      expect(tester.takeException(), isNull);
    });
  });

  group('per-alarm Snooze toggle', () {
    testWidgets('defaults to the current global setting', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final appState = AppState();
      await appState.initialized;
      appState.snoozeEnabled = false;

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

      final snoozeSwitch = tester.widget<Switch>(find.descendant(
        of: find.ancestor(
            of: find.text('Snooze'), matching: find.byType(Card)),
        matching: find.byType(Switch),
      ));
      expect(snoozeSwitch.value, isFalse);
    });

    testWidgets('turning it off produces a ManualAlarm with snoozeEnabled '
        'false', (tester) async {
      final appState = await _openAddDialog(tester);

      final snoozeSwitchFinder = find.descendant(
        of: find.ancestor(
            of: find.text('Snooze'), matching: find.byType(Card)),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(snoozeSwitchFinder);
      await tester.tap(snoozeSwitchFinder);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final created = appState.manualAlarms.single;
      expect(created.snoozeEnabled, isFalse);
    });
  });

  group('per-alarm Guaranteed Wake-Up toggle', () {
    testWidgets('defaults to on for a new alarm', (tester) async {
      await _openAddDialog(tester);

      final gateSwitch = tester.widget<Switch>(find.descendant(
        of: find.ancestor(
            of: find.text('Guaranteed Wake-Up'), matching: find.byType(Card)),
        matching: find.byType(Switch),
      ));
      expect(gateSwitch.value, isTrue);
    });

    testWidgets(
        'turning it off produces a ManualAlarm with requireDeactivationCode '
        'false', (tester) async {
      final appState = await _openAddDialog(tester);

      final gateSwitchFinder = find.descendant(
        of: find.ancestor(
            of: find.text('Guaranteed Wake-Up'), matching: find.byType(Card)),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(gateSwitchFinder);
      await tester.tap(gateSwitchFinder);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final created = appState.manualAlarms.single;
      expect(created.requireDeactivationCode, isFalse);
    });
  });

  group('per-alarm "Counts for Do Not Disturb" toggle (docs/TODO.md T-191, '
      'maintainer request)', () {
    testWidgets('defaults to off for a new alarm - opt-in, unlike the '
        'other two toggles above', (tester) async {
      await _openAddDialog(tester);

      final dndSwitch = tester.widget<Switch>(find.descendant(
        of: find.ancestor(
            of: find.text('Counts for Do Not Disturb'),
            matching: find.byType(Card)),
        matching: find.byType(Switch),
      ));
      expect(dndSwitch.value, isFalse);
    });

    testWidgets(
        'turning it on produces a ManualAlarm with countsForDoNotDisturb '
        'true', (tester) async {
      final appState = await _openAddDialog(tester);

      final dndSwitchFinder = find.descendant(
        of: find.ancestor(
            of: find.text('Counts for Do Not Disturb'),
            matching: find.byType(Card)),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(dndSwitchFinder);
      await tester.tap(dndSwitchFinder);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final created = appState.manualAlarms.single;
      expect(created.countsForDoNotDisturb, isTrue);
    });
  });
}
