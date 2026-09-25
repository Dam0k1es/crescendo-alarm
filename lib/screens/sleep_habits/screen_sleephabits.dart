// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart' show DayOfWeek;
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/sleep_reminder.dart';

class ScreenSleephabits extends StatefulWidget {
  const ScreenSleephabits({super.key});

  /// Test seam, same pattern as `ScreenAlarmActive.debugRingingStreamOverride`
  /// / `QrScanner.debugScanStreamOverride`: replaces the real
  /// `showTimePicker` call with a fake result, so a test can drive every
  /// duration/time control on this screen without operating the actual
  /// Material time-picker dial - no test anywhere in this project does that,
  /// since it's third-party dialog UI, not this screen's own logic to prove
  /// correct. `null` (the default) means the real dialog is used.
  static Future<TimeOfDay?> Function(TimeOfDay? initialTime)?
      debugTimePickerOverride;

  @override
  State<ScreenSleephabits> createState() => _ScreenSleephabitsState();
}

class _ScreenSleephabitsState extends State<ScreenSleephabits> {
  late final AppState _appState;

  // docs/TODO.md T-52.3: purely local UI state - whether to have shown the
  // section at all is not worth persisting, since a user who never opened it
  // has no overrides to look at anyway.
  bool _showGetReadyOverrides = false;

  // docs/TODO.md T-178 (maintainer request): each of the three causal groups
  // below can be collapsed independently - the same "not worth persisting"
  // reasoning as _showGetReadyOverrides above, and expanded by default so
  // every entry is reachable without first discovering the collapse
  // affordance.
  bool _wakeUpTimeExpanded = true;
  bool _whenAlarmRingsExpanded = true;
  bool _bedtimeReminderExpanded = true;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
  }

  Future<TimeOfDay?> _showRealTimePicker(TimeOfDay? initialTime) {
    return showTimePicker(
      context: context,
      initialTime: initialTime ?? const TimeOfDay(hour: 0, minute: 15),
      initialEntryMode: TimePickerEntryMode.dial,
      helpText: 'SELECT TIME',
      cancelText: 'CANCEL',
      confirmText: 'OK',
      hourLabelText: 'Hour',
      minuteLabelText: 'Minute',
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: context.watch<AppState>().accentColor,
                secondary: Theme.of(context).colorScheme.secondary,
                tertiary: Theme.of(context).colorScheme.tertiary,
                surface: Theme.of(context).colorScheme.surface,
                onSurface: Theme.of(context).colorScheme.onSurface,
                onPrimary: Theme.of(context).colorScheme.onPrimary,
                onSecondary: Theme.of(context).colorScheme.onSecondary,
                onTertiary: Theme.of(context).colorScheme.onTertiary,
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            child: child ?? const Text(''),
          ),
        );
      },
    );
  }

  Future<void> _changeDuration(String setting,
      {TimeOfDay? initialTime, DayOfWeek? forWeekday}) async {
    final TimeOfDay? pickedTime =
        await (ScreenSleephabits.debugTimePickerOverride ??
            _showRealTimePicker)(initialTime);

    if (pickedTime != null) {
      if (!mounted) return;
      switch (setting) {
        case 'sleepGoal':
          _appState.sleepGoal = pickedTime;
          Diag.sleepHabitChanged(setting: DiagSleepHabitSetting.sleepGoal);
          break;
        case 'wakeUp':
          _appState.durationToWakeUp = pickedTime;
          Diag.sleepHabitChanged(
              setting: DiagSleepHabitSetting.durationToWakeUp);
          break;
        case 'getReady':
          _appState.durationToGetReady = pickedTime;
          Diag.sleepHabitChanged(
              setting: DiagSleepHabitSetting.durationToGetReady);
          break;
        // docs/TODO.md T-52.3: a per-weekday override, distinct from the
        // global 'getReady' case above.
        case 'getReadyForDay':
          _appState.setDurationToGetReadyForWeekday(forWeekday!, pickedTime);
          Diag.sleepHabitChanged(
              setting: DiagSleepHabitSetting.durationToGetReadyPerWeekday);
          break;
        case 'reminder':
          _appState.reminderDuration = pickedTime;
          Diag.sleepHabitChanged(
              setting: DiagSleepHabitSetting.reminderDuration);
          break;
        // docs/TODO.md T-72: without these two controls, FR-4's drift, FR-7's
        // partial capping, and FR-10's preferredWakeUpTime branch were
        // unreachable for the user - preferredWakeUpTime was always null,
        // maxDailyDelta always the minimum.
        case 'preferredWakeUpTime':
          _appState.preferredWakeUpTime = pickedTime;
          Diag.sleepHabitChanged(
              setting: DiagSleepHabitSetting.preferredWakeUpTime);
          break;
        case 'maxDailyDelta':
          _appState.maxDailyDelta =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
          Diag.sleepHabitChanged(setting: DiagSleepHabitSetting.maxDailyDelta);
          break;
        // docs/TODO.md T-96: how long the gentle-wake ramp takes, i.e. how
        // long the alarm stays quiet. Used to be hardcoded.
        // FR-20: by how much pressing snooze postpones.
        case 'snoozeTime':
          _appState.snoozeTime =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
          Diag.sleepHabitChanged(setting: DiagSleepHabitSetting.snoozeTime);
          break;
        case 'gentleWakeDuration':
          _appState.gentleWakeUpDuration =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
          Diag.sleepHabitChanged(
              setting: DiagSleepHabitSetting.gentleWakeUpDuration);
          break;
      }

      // docs/TODO.md T-65: every one of these four feeds scheduling-v2 - the
      // two durations go into hardFloor (FR-2), sleepGoal/reminderDuration
      // shift the bedtime (FR-16 Checkpoint 2) - and v2's own triggers (ring,
      // once-daily foreground) would otherwise not notice the change until
      // the next day. This replaced the old engine's `scheduleAlarms()` calls
      // here, which Phase 6 then removed entirely (docs/TODO.md T-64).
      await runCheckpointSafely(_appState,
          trigger: CheckpointTrigger.settingsChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
        title: const Text(
          'Sleep Habits',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Three causal groups (docs/TODO.md T-95), each independently
              // collapsible (docs/TODO.md T-178). The order below is itself
              // causal: first what determines the wake-up time, then what
              // happens once the alarm actually rings, then the separate
              // concern of the bedtime reminder (which shifts only itself,
              // never the alarm) last.
              _buildSectionHeader("Wake-up time", _wakeUpTimeExpanded,
                  () => setState(() => _wakeUpTimeExpanded = !_wakeUpTimeExpanded)),
              if (_wakeUpTimeExpanded) ..._buildWakeUpTimeTiles(),

              _buildSectionHeader(
                  "When the alarm rings",
                  _whenAlarmRingsExpanded,
                  () => setState(
                      () => _whenAlarmRingsExpanded = !_whenAlarmRingsExpanded)),
              if (_whenAlarmRingsExpanded) ..._buildWhenAlarmRingsTiles(),

              _buildSectionHeader(
                  "Bedtime reminder",
                  _bedtimeReminderExpanded,
                  () => setState(() =>
                      _bedtimeReminderExpanded = !_bedtimeReminderExpanded)),
              if (_bedtimeReminderExpanded) ..._buildBedtimeReminderTiles(),
            ],
          ),
        ),
      ),
    );
  }

  /// First the target FR-4 drifts toward: the only setting a user needs at
  /// all without calendar appointments. Then the bound on how fast it may
  /// approach it. Then the two lead times, which only apply on days with an
  /// appointment at all - in the order they actually occur in and in which
  /// `hardFloor` subtracts them (wake up first, then get ready).
  List<Widget> _buildWakeUpTimeTiles() {
    return [
      _buildTile(
        help: 'Optional target time the plan drifts toward on days '
            'with no appointment of their own.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToggle(
              "Preferred wake-up time",
              _appState.preferredWakeUpTime != null,
              (value) {
                if (value) {
                  _appState.preferredWakeUpTime =
                      _appState.preferredWakeUpTime ??
                          const TimeOfDay(hour: 7, minute: 0);
                } else {
                  _appState.preferredWakeUpTime = null;
                }
                Diag.sleepHabitChanged(
                    setting: DiagSleepHabitSetting.preferredWakeUpTime);
                runCheckpointSafely(_appState,
                    trigger: CheckpointTrigger.settingsChanged);
              },
            ),
            if (_appState.preferredWakeUpTime != null)
              _buildTimePicker(
                  "preferredWakeUpTime", _appState.preferredWakeUpTime!,
                  isDuration: false),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      // docs/TODO.md T-52.1: whether a day with no calendar entry of its own
      // gets an alarm at all (FR-4's drift/hold) or none.
      _buildTile(
        help: 'On: appointment-free days still get an alarm, '
            'drifting toward your preferred time. Off: those days '
            'get none.',
        child: _buildToggle(
          "Schedule an alarm on days without an appointment",
          _appState.scheduleOnGapDays,
          (value) {
            _appState.scheduleOnGapDays = value;
            Diag.sleepHabitChanged(
                setting: DiagSleepHabitSetting.scheduleOnGapDays);
            runCheckpointSafely(_appState,
                trigger: CheckpointTrigger.settingsChanged);
          },
        ),
      ),
      const SizedBox(height: 8.0),
      // Directly below it, the bound on how fast the wake time may approach
      // this target (FR-6) - it qualifies the entry above and is
      // meaningless without it.
      _buildTile(
        // docs/TODO.md T-88: AppState bounds this value below at 15 minutes
        // (otherwise the smoothing would practically never make progress) -
        // merged into the help text (T-166) rather than a separate
        // always-visible hint, now that the "?" button is the one place
        // this screen explains itself.
        help: 'How much the wake-up time may move per day while '
            'drifting toward your preferred time. Minimum 00:15; '
            'smaller values are raised to that.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("Max. daily shift"),
            _buildTimePicker(
              "maxDailyDelta",
              TimeOfDay(
                hour: _appState.maxDailyDelta.inHours,
                minute: _appState.maxDailyDelta.inMinutes % 60,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      // Then the two lead times. They only apply on days WITH an
      // appointment (FR-2) and therefore come after the target - in the
      // order they actually occur in and in which `hardFloor` subtracts
      // them: wake up first, then get ready.
      _buildTile(
        // FR-20: this same duration is also the snooze budget - the
        // connection isn't guessable, so it's spelled out in the help text
        // (T-166) rather than a separate, snooze-only hint that used to
        // appear beneath this control.
        help: 'Lead time reserved for waking up before an '
            'appointment, and your snooze budget - all snoozes '
            'together may use at most this much.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("Duration to wake up"),
            _buildTimePicker("wakeUp", _appState.durationToWakeUp),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      _buildTile(
        help: 'Lead time reserved for getting ready before an '
            'appointment. Can be overridden per weekday below.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("Duration to get ready"),
            _buildTimePicker("getReady", _appState.durationToGetReady),
            const SizedBox(height: 8.0),
            _buildGetReadyOverridesToggle(),
            if (_showGetReadyOverrides) _buildGetReadyOverrides(),
          ],
        ),
      ),
    ];
  }

  /// docs/TODO.md T-178: moved here from after "Bedtime reminder" - this
  /// group (what happens once the alarm rings) is causally closer to
  /// "wake-up time" (what determines whether/when it rings at all) than the
  /// bedtime reminder is, which shifts only itself, never the alarm.
  List<Widget> _buildWhenAlarmRingsTiles() {
    return [
      _buildTile(
        // As with maxDailyDelta (T-88): the enforced minimum (the alarm
        // plugin requires a genuinely positive duration, but the picker
        // allows 00:00) must not be invisible - merged into the help text
        // (T-166) rather than a separate, ramp-only hint that used to
        // appear beneath the control.
        help: 'Ramps the volume up gradually instead of jumping to '
            'full volume. Minimum 00:01 - the alarm stays quiet at '
            'least that long.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToggle(
              "Gentle WakeUp",
              _appState.gentleWakeUpEnabled,
              (value) {
                _appState.gentleWakeUpEnabled = value;
                Diag.sleepHabitChanged(
                    setting: DiagSleepHabitSetting.gentleWakeUpEnabled);
                // docs/TODO.md T-84: see tone/volume - gentlewake is a
                // property of the already-armed alarms.
                runCheckpointSafely(_appState,
                    trigger: CheckpointTrigger.settingsChanged);
              },
            ),
            // docs/TODO.md T-96: only visible while Gentle Wake is on -
            // without the ramp, the duration has no meaning. Same pattern
            // as the reminder switch below.
            if (_appState.gentleWakeUpEnabled) ...[
              _buildLabel("Ramp duration"),
              _buildTimePicker(
                "gentleWakeDuration",
                TimeOfDay(
                  hour: _appState.gentleWakeUpDuration.inHours,
                  minute: _appState.gentleWakeUpDuration.inMinutes % 60,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      // FR-20. Belongs here, not in the wake-time group: snooze describes
      // what happens when the alarm rings, not when it rings (the same
      // causal grouping as T-95).
      _buildTile(
        // Snooze never switches the alarm off, and never needs the QR code
        // even when stopping does - both non-obvious, so spelled out in the
        // help text (T-166) rather than a separate, snooze-only hint that
        // used to appear beneath the control.
        help: 'Postpones a ringing alarm by a fixed interval, up '
            'to your wake-up budget. Never needs a QR code, and '
            'stops once that budget is used up.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToggle(
              "Snooze",
              _appState.snoozeEnabled,
              (value) {
                // The setter raises `durationToWakeUp` from 00:00 to 00:10
                // on switching on - otherwise the budget would be zero and
                // the feature dead from the start.
                _appState.snoozeEnabled = value;
                Diag.sleepHabitChanged(
                    setting: DiagSleepHabitSetting.snoozeEnabled);
                // The wake time itself changes as a result (FR-2 subtracts
                // `durationToWakeUp`), so a replan is needed.
                runCheckpointSafely(_appState,
                    trigger: CheckpointTrigger.settingsChanged);
              },
            ),
            if (_appState.snoozeEnabled) ...[
              _buildLabel("Snooze time"),
              _buildTimePicker(
                "snoozeTime",
                TimeOfDay(
                  hour: _appState.snoozeTime.inHours,
                  minute: _appState.snoozeTime.inMinutes % 60,
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// The sleep goal defines the bedtime (wake time - sleepGoal -
  /// reminderDuration, see lib/utils/sleep_reminder.dart) and does NOT
  /// touch the alarm time - a separate concern from the two groups above,
  /// so it comes last (docs/TODO.md T-178).
  List<Widget> _buildBedtimeReminderTiles() {
    return [
      _buildTile(
        help: 'How much sleep you\'re aiming for. Shifts the '
            'bedtime reminder below, not the alarm itself.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("Sleep Goal"),
            _buildSleepGoalPicker(_appState.sleepGoal),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      // The lead time is measured from the bedtime the entry above sets -
      // the two belong side by side.
      _buildTile(
        help: 'A notification reminding you to go to bed, timed '
            'this far before your Sleep Goal\'s bedtime.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToggle(
              "Enable Reminder",
              _appState.reminderEnabled,
              (value) {
                _appState.reminderEnabled = value;
                Diag.sleepHabitChanged(
                    setting: DiagSleepHabitSetting.reminderEnabled);
                // FR-16 "precondition": scheduled unconditionally -
                // silently (no visible notification) when disabled, still
                // needed as Checkpoint 2's hook.
                scheduleSleepReminder(_appState);
              },
            ),
            if (_appState.reminderEnabled)
              _buildTimePicker("reminder", _appState.reminderDuration),
          ],
        ),
      ),
    ];
  }

  /// docs/TODO.md T-20: [help], when given, renders as a "?" button pinned
  /// to the tile's top-right corner. A `Tooltip` (tap-triggered) was tried
  /// first, but its tap gesture proved unreliable once embedded in this
  /// screen's `SingleChildScrollView` with several tiles stacked on top of
  /// each other - it worked in isolation, not here, and chasing gesture-arena
  /// interactions with the scroll view wasn't worth it for a "?" button.
  /// A plain `IconButton` showing a `SnackBar` is simpler, exercises only
  /// well-tested Material widgets, and is just as compact on a phone screen.
  Widget _buildTile({required Widget child, String? help}) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: child,
      ),
      // color: Theme.of(context).colorScheme.onPrimary,
    );
    if (help == null) return card;
    return Stack(
      children: [
        card,
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            icon: Icon(
              Icons.help_outline,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8.0),
            constraints: const BoxConstraints(),
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(help)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(
      String label, bool currentValue, Function(bool) toggleFunction) {
    return SwitchListTile(
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 20,
        ),
      ),
      value: currentValue,
      onChanged: toggleFunction,
      activeThumbColor:
          context.watch<AppState>().accentColor.withValues(alpha: 0.05),
    );
  }

  Widget _buildSleepGoalPicker(TimeOfDay sleepGoal) {
    return GestureDetector(
      key: const Key('timePicker_sleepGoal'),
      onTap: () =>
          _changeDuration('sleepGoal', initialTime: _appState.sleepGoal),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTimeBox(sleepGoal.hour.toString().padLeft(2, '0')),
            const Text(":",
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            _buildTimeBox(sleepGoal.minute.toString().padLeft(2, '0')),
            const Text(" h",
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
      ),
    );
  }

  /// [isDuration] decides the suffix: most controls here are durations
  /// ("01:30 h"), while the preferred wake-up time (FR-3) is a time of day
  /// and was wrongly labelled as a duration by the shared picker
  /// (docs/TODO.md T-88).
  Widget _buildTimePicker(String setting, TimeOfDay value,
      {bool isDuration = true}) {
    return GestureDetector(
      key: Key('timePicker_$setting'),
      onTap: () => _changeDuration(setting, initialTime: value),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTimeBox(value.hour.toString().padLeft(2, '0')),
            const Text(":",
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            _buildTimeBox(value.minute.toString().padLeft(2, '0')),
            Text(isDuration ? " h" : " Uhr",
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBox(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// docs/TODO.md T-52.3: a plain text toggle rather than a full tile - this
  /// section is a secondary, optional refinement of the setting above it,
  /// not a peer entry of its own.
  Widget _buildGetReadyOverridesToggle() {
    return Center(
      child: InkWell(
        onTap: () =>
            setState(() => _showGetReadyOverrides = !_showGetReadyOverrides),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _showGetReadyOverrides
                  ? "Hide per-weekday overrides"
                  : "Customize per weekday",
              style: TextStyle(
                fontSize: 14,
                color: _appState.accentColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One row per [DayOfWeek]: a switch for whether that day overrides the
  /// global "duration to get ready" at all, and - only while it does - the
  /// same time-box picker the global setting itself uses. Absent an
  /// override, [AppState.durationToGetReadyForWeekday] falls back to the
  /// global value, which is exactly what the switch being off means here.
  Widget _buildGetReadyOverrides() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in DayOfWeek.values)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(_dayLabel(day)),
                ),
                Switch(
                  key: Key('getReadyOverrideSwitch_${day.name}'),
                  value: _appState.durationToGetReadyByWeekday.containsKey(day),
                  onChanged: (value) {
                    _appState.setDurationToGetReadyForWeekday(
                        day,
                        value
                            ? _appState.durationToGetReadyForWeekday(day)
                            : null);
                    Diag.sleepHabitChanged(
                        setting:
                            DiagSleepHabitSetting.durationToGetReadyPerWeekday);
                    runCheckpointSafely(_appState,
                        trigger: CheckpointTrigger.settingsChanged);
                  },
                  activeThumbColor: context
                      .watch<AppState>()
                      .accentColor
                      .withValues(alpha: 0.05),
                ),
                if (_appState.durationToGetReadyByWeekday.containsKey(day))
                  GestureDetector(
                    key: Key('timePicker_getReadyForDay_${day.name}'),
                    onTap: () => _changeDuration('getReadyForDay',
                        initialTime:
                            _appState.durationToGetReadyForWeekday(day),
                        forWeekday: day),
                    child: Text(
                      '${_appState.durationToGetReadyForWeekday(day).hour.toString().padLeft(2, '0')}:'
                      '${_appState.durationToGetReadyForWeekday(day).minute.toString().padLeft(2, '0')} h',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _dayLabel(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.monday:
        return 'Monday';
      case DayOfWeek.tuesday:
        return 'Tuesday';
      case DayOfWeek.wednesday:
        return 'Wednesday';
      case DayOfWeek.thursday:
        return 'Thursday';
      case DayOfWeek.friday:
        return 'Friday';
      case DayOfWeek.saturday:
        return 'Saturday';
      case DayOfWeek.sunday:
        return 'Sunday';
    }
  }

  /// A heading for a group of entries. Without it, the grouping would be
  /// invisible to the user and the order just a different one, not an
  /// explained one (docs/TODO.md T-95). The top spacing is larger than the
  /// spacing between tiles, so the groups visually stand apart.
  ///
  /// docs/TODO.md T-178 (maintainer request): the whole row is now one
  /// tappable area toggling [expanded] via [onToggle] - clicking the
  /// heading text or the small chevron on its right both work, since both
  /// sit inside the same `InkWell`.
  Widget _buildSectionHeader(
          String text, bool expanded, VoidCallback onToggle) =>
      Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: _appState.accentColor,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: _appState.accentColor,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}
