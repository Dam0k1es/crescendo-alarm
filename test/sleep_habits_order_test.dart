import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/sleep_habits/screen_sleephabits.dart';

// docs/TODO.md T-95: the order of entries on the sleep-habits screen.
//
// The defect in the old order was not taste, but a wrong attribution of
// cause: "Sleep Goal" was in first place, but doesn't affect the alarm time
// at all - it only shifts the bedtime reminder (nextWakeUpTime - sleepGoal -
// reminderDuration, see lib/utils/sleep_reminder.dart). Whoever sees it at
// the top and adjusts it expects an earlier alarm and gets nothing. At the
// same time it was separated from "Enable Reminder" - its other half of the
// same calculation - by three unrelated entries, and "Preferred wake-up
// time", the anchor of the entire FR-4 drift and the only setting a user
// needs at all without calendar appointments, sat at position 4, below two
// durations that only apply when an appointment exists.
//
// Tested via the labels' y-position, not the source order: what's checked is
// what the user sees.

Future<AppState> _appStateWithAllTilesVisible() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  // Open both expandable sections, so every entry is in the tree.
  appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  appState.reminderEnabled = true;
  appState.gentleWakeUpEnabled = true;
  return appState;
}

Future<void> _pumpScreen(WidgetTester tester, AppState appState) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSleephabits()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The y-positions of the named texts, in the list's order.
List<double> _verticalPositions(WidgetTester tester, List<String> labels) {
  return labels.map((label) {
    final finder = find.text(label);
    expect(finder, findsOneWidget,
        reason: 'label "$label" not found (or found more than once)');
    return tester.getTopLeft(finder).dy;
  }).toList();
}

void main() {
  testWidgets('the entries are in causal order', (tester) async {
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    // Three groups, each internally ordered by cause:
    //
    // 1. What determines WHEN the alarm rings. First the target FR-4 drifts
    //    toward; then the bound on how fast it may approach it; then the two
    //    lead times, which only apply on days with an appointment at all -
    //    in the order they actually occur in and in which hardFloor
    //    subtracts them (wake up first, then get ready).
    // 2. How the alarm behaves once it rings.
    // 3. What determines the bedtime reminder. The sleep goal defines the
    //    bedtime, the lead time is measured from it - hence this order.
    //
    // docs/TODO.md T-178 (maintainer request): groups 2 and 3 swapped from
    // their previous order - "when the alarm rings" now comes directly
    // after "wake-up time", with the bedtime reminder (a separate concern -
    // it shifts the reminder, never the alarm itself) last.
    final expectedOrder = <String>[
      'Preferred wake-up time',
      'Max. daily shift',
      'Duration to wake up',
      'Duration to get ready',
      'Gentle WakeUp',
      'Sleep Goal',
      'Enable Reminder',
    ];

    final positions = _verticalPositions(tester, expectedOrder);

    for (var i = 1; i < positions.length; i++) {
      expect(
        positions[i],
        greaterThan(positions[i - 1]),
        reason: '"${expectedOrder[i]}" must be below "${expectedOrder[i - 1]}" '
            'but is at y=${positions[i]} versus '
            'y=${positions[i - 1]}',
      );
    }
  });

  testWidgets('each group carries a heading above its first entry',
      (tester) async {
    // Without headings the grouping is invisible to the user - then the new
    // order would just be a different one, not an explained one.
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    final pairs = <String, String>{
      'Wake-up time': 'Preferred wake-up time',
      'Bedtime reminder': 'Sleep Goal',
      'When the alarm rings': 'Gentle WakeUp',
    };

    pairs.forEach((header, firstItem) {
      final headerFinder = find.text(header);
      expect(headerFinder, findsOneWidget,
          reason: 'group heading "$header" is missing');
      expect(
        tester.getTopLeft(headerFinder).dy,
        lessThan(tester.getTopLeft(find.text(firstItem)).dy),
        reason: '"$header" must be above "$firstItem"',
      );
    });
  });

  // docs/TODO.md T-166: the always-visible "smaller values are raised to
  // 00:15" hint was merged into the "?" help text once T-20 gave this
  // screen a single place to explain itself - see
  // test/screen_sleephabits_help_test.dart for the guard that the merged
  // content is actually still there, not just dropped.

  // docs/TODO.md T-96: Gentle Wake had no control - the ramp was hardcoded to
  // 60 seconds.
  testWidgets('Gentle Wake shows a control for the ramp duration',
      (tester) async {
    await _pumpScreen(tester, await _appStateWithAllTilesVisible());

    final label = find.text('Ramp duration');
    expect(label, findsOneWidget, reason: 'ramp-duration control is missing');
    expect(
      tester.getTopLeft(label).dy,
      greaterThan(tester.getTopLeft(find.text('Gentle WakeUp')).dy),
      reason: 'the control belongs below its switch',
    );
    // The enforced minimum (the hh:mm picker allows 00:00, the plugin does
    // not) used to have its own always-visible hint here; it's now part of
    // this tile's "?" help text instead (docs/TODO.md T-166) - see
    // test/screen_sleephabits_help_test.dart.
  });

  testWidgets('with Gentle Wake off, there is also no control', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;
    appState.gentleWakeUpEnabled = false;
    await _pumpScreen(tester, appState);

    expect(find.text('Ramp duration'), findsNothing);
  });
}
