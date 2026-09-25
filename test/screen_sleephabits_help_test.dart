import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/sleep_habits/screen_sleephabits.dart';

// docs/TODO.md T-20: every Sleep-Habits option gets a "?" help button in its
// top-right corner, showing a short, on-screen explanation on tap.
//
// A Tooltip with `triggerMode: TooltipTriggerMode.tap` was tried first, but
// its tap gesture proved unreliable once embedded in this screen's
// SingleChildScrollView with several tiles stacked on top of each other -
// it worked fine in an isolated repro, not here. An IconButton showing a
// SnackBar is what's actually implemented: a plain, well-tested Material
// interaction instead of chasing gesture-arena behaviour.

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
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

void main() {
  testWidgets('every Sleep-Habits option has a help button', (tester) async {
    final appState = await _freshAppState();
    await _pumpScreen(tester, appState);

    // One per option tile: preferred wake-up time, gap-day scheduling, max
    // daily shift, duration to wake up, duration to get ready, sleep goal,
    // reminder, gentle wake-up, snooze.
    expect(find.byIcon(Icons.help_outline), findsNWidgets(9));
  });

  testWidgets('tapping a help button shows a concise, on-screen explanation',
      (tester) async {
    final appState = await _freshAppState();
    await _pumpScreen(tester, appState);

    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pump(); // SnackBar enters via an animation, not settled yet.

    final snackBarText =
        tester.widget<Text>(find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Text),
    ));
    final message = snackBarText.data!;

    expect(message.trim(), isNotEmpty);
    // "Concise enough to read on a phone" - not a hard limit, but a plain
    // sanity bound against accidentally pasting a paragraph in here.
    expect(message.length, lessThanOrEqualTo(140),
        reason: 'help text too long for a phone: "$message"');
  });

  testWidgets('every help button has its own concise explanation',
      (tester) async {
    // A fresh widget tree per icon (torn down via an unrelated tree first,
    // not just re-pumping an equivalently-shaped one): Flutter reuses
    // State - including ScaffoldMessenger's - across pumpWidget calls that
    // build the same widget shape, so a previous iteration's SnackBar can
    // otherwise leak into the next. Later tiles also need `ensureVisible`:
    // the screen scrolls, so their help icons exist in the tree but start
    // outside the visible viewport, where a tap can't land on them.
    final messages = <String>{};
    for (var i = 0; i < 9; i++) {
      await tester.pumpWidget(const SizedBox.shrink());
      final appState = await _freshAppState();
      await _pumpScreen(tester, appState);

      final icon = find.byIcon(Icons.help_outline).at(i);
      await tester.ensureVisible(icon);
      await tester.pumpAndSettle();
      await tester.tap(icon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final text = tester
          .widget<Text>(find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ))
          .data!;
      expect(text.trim(), isNotEmpty);
      expect(text.length, lessThanOrEqualTo(140),
          reason: 'help text too long for a phone: "$text"');
      messages.add(text);
    }
    expect(messages.length, 9,
        reason: 'every option should have its own explanation, not a '
            'copy-pasted shared one');
  });

  // docs/TODO.md T-166: four tiles used to carry a second, always-visible
  // explanatory Text widget below their control (an enforced-minimum hint,
  // or a snooze-budget/QR-code note) alongside their "?" help button - once
  // T-20 gave every option a single place to explain itself, those became
  // redundant and were removed from the layout. This guards that their
  // *content* survived the merge into the help text rather than being
  // silently dropped - a source-reading test would only catch the string
  // moving file, not whether the information it carried is still there.
  group('content merged from the removed inline hints (T-166)', () {
    Future<String> helpTextAt(WidgetTester tester, int index) async {
      final appState = await _freshAppState();
      await _pumpScreen(tester, appState);

      final icon = find.byIcon(Icons.help_outline).at(index);
      await tester.ensureVisible(icon);
      await tester.pumpAndSettle();
      await tester.tap(icon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return tester
          .widget<Text>(find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ))
          .data!;
    }

    testWidgets('"Max. daily shift" still documents the enforced minimum',
        (tester) async {
      final text = await helpTextAt(tester, 2);
      expect(text, contains('00:15'));
    });

    testWidgets('"Duration to wake up" still documents the snooze budget',
        (tester) async {
      final text = await helpTextAt(tester, 3);
      expect(text.toLowerCase(), contains('snooze'));
    });

    testWidgets('"Gentle WakeUp" still documents the enforced minimum',
        (tester) async {
      final text = await helpTextAt(tester, 7);
      expect(text, contains('00:01'));
    });

    testWidgets('"Snooze" still documents no-QR-code and the used-up budget',
        (tester) async {
      final text = await helpTextAt(tester, 8);
      expect(text, contains('QR'));
      expect(text.toLowerCase(), contains('used up'));
    });
  });
}
