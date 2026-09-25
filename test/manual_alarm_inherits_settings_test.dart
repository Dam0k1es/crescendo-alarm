import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';

// docs/TODO.md T-96: the dialog for creating a manual alarm pre-fills
// gentlewake, volume and tone from the AppState (screen_alarms.dart:265-267)
// - but not, initially, the new ramp duration. A manual alarm would
// therefore have stubbornly used the default minute and ignored the
// user's setting. That is exactly the bug class from T-84: a setting with
// a UI that never reaches the alarm.

void main() {
  testWidgets('a new manual alarm inherits ramp duration, volume, and tone',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;
    appState.gentleWakeUpEnabled = true;
    appState.gentleWakeUpDuration = const Duration(minutes: 9);
    appState.selectedVolume = 0.42;
    appState.vibrationEnabled = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pumpAndSettle();

    // Since T-137 the screen opens on "Scheduled"; the Add button belongs
    // to the Manual tab (on "Scheduled" that spot holds the sync button).
    // So switch there first - this test's assertion is unchanged, only
    // the path to the dialog is one step longer.
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final created = appState.manualAlarms.single;
    expect(created.gentlewake, isTrue);
    expect(created.gentleWakeDuration, const Duration(minutes: 9),
        reason: 'the configured ramp duration must reach the alarm - '
            'otherwise it is T-84 all over again');
    // The other two, which were already carried over before - as a
    // safeguard that the pre-fill as a whole stays intact.
    expect(created.volume, 0.42);
    expect(created.tone, appState.selectedTone);
    // docs/TODO.md T-50: vibrate is the newest of these settings - same
    // inheritance rule, same failure class if it were skipped.
    expect(created.vibrate, isFalse);
  });
}
