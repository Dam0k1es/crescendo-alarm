import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart' show DayOfWeek;
import 'package:crescendo_alarm/screens/sleep_habits/screen_sleephabits.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';

// docs/TODO.md T-173 (maintainer request): "the logs should be extended
// whenever any Sleep Habits setting changes, no matter which". Diag.
// sleepHabitChanged carries only WHICH setting changed, never the value -
// most of these settings are clock-shaped, and this log structurally
// excludes clock values everywhere except the three fields already gated
// behind the opt-in clock-time switch (test/diag_log_api_test.dart).
//
// The 8 duration/time-of-day controls on this screen go through the real
// Material showTimePicker dialog - no test in this project drives that
// dialog directly (it's third-party UI, not this screen's own logic), so
// ScreenSleephabits.debugTimePickerOverride (same seam shape as
// ScreenAlarmActive.debugRingingStreamOverride / QrScanner.
// debugScanStreamOverride) replaces it with a fake result instead.

Future<AppState> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  Diag.resetForTest();

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: ScreenSleephabits()),
    ),
  );
  await tester.pumpAndSettle();
  return appState;
}

Future<void> _tapTimePicker(WidgetTester tester, String key,
    {TimeOfDay result = const TimeOfDay(hour: 3, minute: 33)}) async {
  ScreenSleephabits.debugTimePickerOverride = (_) async => result;
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  ScreenSleephabits.debugTimePickerOverride = null;
}

List<int> _settingsLogged() => Diag.records
    .where((r) => r.event == DiagEvent.sleepHabitChanged)
    .map((r) => r.fields[DiagField.sleepHabitSetting]!)
    .toList();

/// Several of these toggles sit below the fold on the 800x600 test
/// viewport - a bare `tester.tap` misses them silently otherwise (the same
/// scroll trap `test/page_alarmtones_custom_tones_test.dart` and others
/// already needed `tester.ensureVisible()` for).
Future<void> _tapToggle(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SwitchListTile, label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    ScreenSleephabits.debugTimePickerOverride = null;
  });

  group('one Diag.sleepHabitChanged event per changed setting', () {
    testWidgets('sleepGoal', (tester) async {
      await _pumpScreen(tester);
      await _tapTimePicker(tester, 'timePicker_sleepGoal');
      expect(_settingsLogged(), [DiagSleepHabitSetting.sleepGoal.code]);
    });

    testWidgets('durationToWakeUp', (tester) async {
      await _pumpScreen(tester);
      await _tapTimePicker(tester, 'timePicker_wakeUp');
      expect(
          _settingsLogged(), [DiagSleepHabitSetting.durationToWakeUp.code]);
    });

    testWidgets('durationToGetReady', (tester) async {
      await _pumpScreen(tester);
      await _tapTimePicker(tester, 'timePicker_getReady');
      expect(
          _settingsLogged(), [DiagSleepHabitSetting.durationToGetReady.code]);
    });

    testWidgets(
        'durationToGetReadyPerWeekday - enabling a per-weekday override',
        (tester) async {
      await _pumpScreen(tester);
      final expandLink = find.text('Customize per weekday');
      await tester.ensureVisible(expandLink);
      await tester.tap(expandLink);
      await tester.pumpAndSettle();

      final mondaySwitch = find.byKey(const Key('getReadyOverrideSwitch_monday'));
      await tester.ensureVisible(mondaySwitch);
      await tester.tap(mondaySwitch);
      await tester.pumpAndSettle();

      expect(_settingsLogged(),
          [DiagSleepHabitSetting.durationToGetReadyPerWeekday.code]);
    });

    testWidgets(
        'durationToGetReadyPerWeekday - changing an already-overridden day',
        (tester) async {
      final appState = await _pumpScreen(tester);
      final expandLink = find.text('Customize per weekday');
      await tester.ensureVisible(expandLink);
      await tester.tap(expandLink);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('getReadyOverrideSwitch_monday')));
      await tester.pumpAndSettle();
      expect(appState.durationToGetReadyByWeekday.containsKey(DayOfWeek.monday),
          isTrue);
      Diag.resetForTest();

      await _tapTimePicker(tester, 'timePicker_getReadyForDay_monday');

      expect(_settingsLogged(),
          [DiagSleepHabitSetting.durationToGetReadyPerWeekday.code]);
    });

    testWidgets('reminderDuration', (tester) async {
      await _pumpScreen(tester);
      await _tapToggle(tester, 'Enable Reminder');
      Diag.resetForTest();

      await _tapTimePicker(tester, 'timePicker_reminder');

      expect(
          _settingsLogged(), [DiagSleepHabitSetting.reminderDuration.code]);
    });

    testWidgets('preferredWakeUpTime - switching it on', (tester) async {
      await _pumpScreen(tester);
      await tester
          .tap(find.widgetWithText(SwitchListTile, 'Preferred wake-up time'));
      await tester.pumpAndSettle();
      expect(
          _settingsLogged(), [DiagSleepHabitSetting.preferredWakeUpTime.code]);
    });

    testWidgets('preferredWakeUpTime - changing the value once on',
        (tester) async {
      await _pumpScreen(tester);
      await tester
          .tap(find.widgetWithText(SwitchListTile, 'Preferred wake-up time'));
      await tester.pumpAndSettle();
      Diag.resetForTest();

      await _tapTimePicker(tester, 'timePicker_preferredWakeUpTime');

      expect(
          _settingsLogged(), [DiagSleepHabitSetting.preferredWakeUpTime.code]);
    });

    testWidgets('maxDailyDelta', (tester) async {
      await _pumpScreen(tester);
      await _tapTimePicker(tester, 'timePicker_maxDailyDelta');
      expect(_settingsLogged(), [DiagSleepHabitSetting.maxDailyDelta.code]);
    });

    testWidgets('snoozeTime - visible by default (T-170: snoozeEnabled on)',
        (tester) async {
      final appState = await _pumpScreen(tester);
      expect(appState.snoozeEnabled, isTrue);

      await _tapTimePicker(tester, 'timePicker_snoozeTime');

      expect(_settingsLogged(), [DiagSleepHabitSetting.snoozeTime.code]);
    });

    testWidgets(
        'gentleWakeUpDuration - visible by default '
        '(T-170: gentleWakeUpEnabled on)', (tester) async {
      final appState = await _pumpScreen(tester);
      expect(appState.gentleWakeUpEnabled, isTrue);

      await _tapTimePicker(tester, 'timePicker_gentleWakeDuration');

      expect(
          _settingsLogged(), [DiagSleepHabitSetting.gentleWakeUpDuration.code]);
    });

    testWidgets('scheduleOnGapDays', (tester) async {
      await _pumpScreen(tester);
      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Schedule an alarm on days without an appointment'));
      await tester.pumpAndSettle();
      expect(_settingsLogged(), [DiagSleepHabitSetting.scheduleOnGapDays.code]);
    });

    testWidgets('reminderEnabled', (tester) async {
      await _pumpScreen(tester);
      await _tapToggle(tester, 'Enable Reminder');
      expect(_settingsLogged(), [DiagSleepHabitSetting.reminderEnabled.code]);
    });

    testWidgets('gentleWakeUpEnabled', (tester) async {
      await _pumpScreen(tester);
      await _tapToggle(tester, 'Gentle WakeUp');
      expect(
          _settingsLogged(), [DiagSleepHabitSetting.gentleWakeUpEnabled.code]);
    });

    testWidgets('snoozeEnabled', (tester) async {
      await _pumpScreen(tester);
      await _tapToggle(tester, 'Snooze');
      expect(_settingsLogged(), [DiagSleepHabitSetting.snoozeEnabled.code]);
    });
  });

  testWidgets(
      'every DiagSleepHabitSetting value is reachable from this screen - '
      'a new setting added here without a matching Diag call would leave '
      'this list stale, not the enum wrong', (tester) async {
    // Not a functional test - documents the enum's completeness against
    // the 13 real controls above, so the two can't silently drift apart.
    expect(DiagSleepHabitSetting.values.length, 13);
  });
}
