import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/sleep_habits/screen_sleephabits.dart';

// docs/TODO.md T-178 (maintainer request): each of the three causal groups
// (T-95) on the Sleep Habits screen can now be collapsed independently, by
// tapping its heading or the small chevron marker on its right - purely
// local UI state, not persisted, the same precedent
// `_showGetReadyOverrides` (T-52.3) already established for this screen: a
// user who never collapsed a section has nothing to restore anyway.
//
// Expanded by default, so every other test on this screen (which pumps it
// and expects every entry findable without first expanding anything)
// continues to work unchanged.

Future<AppState> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSleephabits()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  testWidgets('every group heading is expanded by default', (tester) async {
    await _pumpScreen(tester);

    // One collapse-indicator icon per heading, all in the "expanded" state.
    expect(find.byIcon(Icons.expand_less), findsNWidgets(3));
    expect(find.byIcon(Icons.expand_more), findsNothing);

    // Every entry (from all three groups) is already visible with no tap.
    expect(find.text('Preferred wake-up time'), findsOneWidget);
    expect(find.text('Duration to get ready'), findsOneWidget);
    expect(find.text('Sleep Goal'), findsOneWidget);
  });

  testWidgets('tapping a heading collapses its own group only', (tester) async {
    await _pumpScreen(tester);

    final heading = find.text('Wake-up time');
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pumpAndSettle();

    expect(find.text('Preferred wake-up time'), findsNothing,
        reason: 'the collapsed group\'s own entries must be hidden');
    expect(find.text('Duration to get ready'), findsNothing,
        reason: 'the collapsed group\'s own entries must be hidden');
    // Unrelated groups stay exactly as they were.
    expect(find.text('Gentle WakeUp'), findsOneWidget);
    expect(find.text('Sleep Goal'), findsOneWidget);
  });

  testWidgets('tapping a collapsed heading again re-expands it',
      (tester) async {
    await _pumpScreen(tester);

    final heading = find.text('When the alarm rings');
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pumpAndSettle();
    expect(find.text('Gentle WakeUp'), findsNothing);

    await tester.tap(heading);
    await tester.pumpAndSettle();
    expect(find.text('Gentle WakeUp'), findsOneWidget);
  });

  testWidgets(
      'tapping the small chevron marker on the right toggles the group too',
      (tester) async {
    await _pumpScreen(tester);

    // The heading and its chevron sit in one tappable row (docs/TODO.md
    // T-178: "durch klicken auf diese (oder eine kleine markierung
    // rechts)") - tapping the icon specifically, not the text, must work
    // just as well.
    final chevron = find
        .descendant(
          of: find.ancestor(
              of: find.text('Bedtime reminder'), matching: find.byType(Row)),
          matching: find.byIcon(Icons.expand_less),
        )
        .first;
    await tester.ensureVisible(chevron);
    await tester.tap(chevron);
    await tester.pumpAndSettle();

    expect(find.text('Sleep Goal'), findsNothing);
    expect(find.text('Enable Reminder'), findsNothing);
  });

  testWidgets('collapsing every group leaves only the three headings',
      (tester) async {
    await _pumpScreen(tester);

    for (final heading in [
      'Wake-up time',
      'When the alarm rings',
      'Bedtime reminder',
    ]) {
      final finder = find.text(heading);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    expect(find.byIcon(Icons.expand_more), findsNWidgets(3));
    expect(find.text('Preferred wake-up time'), findsNothing);
    expect(find.text('Gentle WakeUp'), findsNothing);
    expect(find.text('Sleep Goal'), findsNothing);
    // The three headings themselves are never hidden - only their content.
    expect(find.text('Wake-up time'), findsOneWidget);
    expect(find.text('When the alarm rings'), findsOneWidget);
    expect(find.text('Bedtime reminder'), findsOneWidget);
  });
}
