import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/main.dart';

// docs/TODO.md T-60: while the app is (re-)reading the calendar, the
// Schedule tab shows a small spinner in place of its static icon - the only
// visible sign that the calendar fetch T-60 now runs on every app open is
// actually happening, since it can take a moment on a large calendar.
void main() {
  testWidgets(
      'the Schedule tab shows a spinner while isReadingCalendarMutex is set',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    appState.permissionsGranted = true; // skip the splash screen

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MyApp(),
      ),
    );
    await tester.pump();

    final navBarCalendarIcon = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.byIcon(Icons.calendar_month),
    );

    expect(navBarCalendarIcon, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    appState.isReadingCalendarMutex = true;
    await tester.pump();

    expect(navBarCalendarIcon, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    appState.isReadingCalendarMutex = false;
    await tester.pump();

    expect(navBarCalendarIcon, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
