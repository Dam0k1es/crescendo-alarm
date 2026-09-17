import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/utils/sleep_reminder.dart';

// TODO durationToGetReady per weekday - 0x399

class ScreenSleephabits extends StatefulWidget {
  const ScreenSleephabits({super.key});

  @override
  State<ScreenSleephabits> createState() => _ScreenSleephabitsState();
}

class _ScreenSleephabitsState extends State<ScreenSleephabits> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
  }

  Future<void> _changeDuration(String setting, {TimeOfDay? initialTime}) async {
    final TimeOfDay? pickedTime = await showTimePicker(
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

    if (pickedTime != null) {
      if (!mounted) return;
      switch (setting) {
        case 'sleepGoal':
          _appState.sleepGoal = pickedTime;
          break;
        case 'wakeUp':
          _appState.durationToWakeUp = pickedTime;
          break;
        case 'getReady':
          _appState.durationToGetReady = pickedTime;
          break;
        case 'reminder':
          _appState.reminderDuration = pickedTime;
          break;
        // docs/TODO.md T-72: without these two controls, FR-4's drift, FR-7's
        // partial capping, and FR-10's preferredWakeUpTime branch were
        // unreachable for the user - preferredWakeUpTime was always null,
        // maxDailyDelta always the minimum.
        case 'preferredWakeUpTime':
          _appState.preferredWakeUpTime = pickedTime;
          break;
        case 'maxDailyDelta':
          _appState.maxDailyDelta =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
          break;
        // docs/TODO.md T-96: how long the gentle-wake ramp takes, i.e. how
        // long the alarm stays quiet. Used to be hardcoded.
        // FR-20: by how much pressing snooze postpones.
        case 'snoozeTime':
          _appState.snoozeTime =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
          break;
        case 'gentleWakeDuration':
          _appState.gentleWakeUpDuration =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
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
              // Three causal groups (docs/TODO.md T-95). The previous order
              // was misleading: "Sleep Goal" was at the top, but doesn't
              // affect the alarm time at all - it only shifts the bedtime
              // reminder - and was separated from "Enable Reminder", its
              // other half of the same calculation, by three unrelated
              // entries.
              _buildSectionHeader("Wake-up time"),
              // First the target FR-4 drifts toward: the only setting a user
              // needs at all without calendar appointments.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Preferred wake-up time",
                      _appState.preferredWakeUpTime != null,
                      (value) {
                        if (value) {
                          _appState.preferredWakeUpTime =
                              _appState.preferredWakeUpTime ?? const TimeOfDay(hour: 7, minute: 0);
                        } else {
                          _appState.preferredWakeUpTime = null;
                        }
                        runCheckpointSafely(_appState,
                            trigger: CheckpointTrigger.settingsChanged);
                      },
                    ),
                    if (_appState.preferredWakeUpTime != null)
                      _buildTimePicker("preferredWakeUpTime", _appState.preferredWakeUpTime!,
                          isDuration: false),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              // Directly below it, the bound on how fast the wake time may
              // approach this target (FR-6) - it qualifies the entry above
              // and is meaningless without it.
              _buildTile(
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
                    // docs/TODO.md T-88: AppState bounds this value below at
                    // 15 minutes (otherwise the smoothing would practically
                    // never make progress). That was invisible to the user -
                    // whoever picked 5 minutes silently got 15.
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        'At least 00:15 h - smaller values are raised to that.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              // Then the two lead times. They only apply on days WITH an
              // appointment (FR-2) and therefore come after the target - in
              // the order they actually occur in and in which `hardFloor`
              // subtracts them: wake up first, then get ready.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Duration to wake up"),
                    _buildTimePicker("wakeUp", _appState.durationToWakeUp),
                    // FR-20: this same duration is the snooze budget. The
                    // connection isn't guessable, so it's spelled out here -
                    // but only while snooze is actually on.
                    if (_appState.snoozeEnabled)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Also your snooze budget: all snoozes together may '
                          'push a wake-up by at most this much, so the time '
                          'you need to get ready stays untouched.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Duration to get ready"),
                    _buildTimePicker("getReady", _appState.durationToGetReady),
                  ],
                ),
              ),

              _buildSectionHeader("Bedtime reminder"),
              // The sleep goal defines the bedtime
              // (wake time - sleepGoal - reminderDuration, see
              // lib/utils/sleep_reminder.dart) and does NOT touch the alarm
              // time. Hence here, not in the group above.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Sleep Goal"),
                    _buildSleepGoalPicker(_appState.sleepGoal),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              // The lead time is measured from the bedtime the entry above
              // sets - the two belong side by side.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Enable Reminder",
                      _appState.reminderEnabled,
                      (value) {
                        _appState.reminderEnabled = value;
                        // FR-16 "precondition": scheduled unconditionally -
                        // silently (no visible notification) when disabled,
                        // still needed as Checkpoint 2's hook.
                        scheduleSleepReminder(_appState);
                      },
                    ),
                    if (_appState.reminderEnabled)
                      _buildTimePicker("reminder", _appState.reminderDuration),
                  ],
                ),
              ),

              _buildSectionHeader("When the alarm rings"),
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Gentle WakeUp",
                      _appState.gentleWakeUpEnabled,
                      (value) {
                        _appState.gentleWakeUpEnabled = value;
                        // docs/TODO.md T-84: see tone/volume - gentlewake is
                        // a property of the already-armed alarms.
                        runCheckpointSafely(_appState,
                            trigger: CheckpointTrigger.settingsChanged);
                      },
                    ),
                    // docs/TODO.md T-96: only visible while Gentle Wake is
                    // on - without the ramp, the duration has no meaning.
                    // Same pattern as the reminder switch above.
                    if (_appState.gentleWakeUpEnabled) ...[
                      _buildLabel("Ramp duration"),
                      _buildTimePicker(
                        "gentleWakeDuration",
                        TimeOfDay(
                          hour: _appState.gentleWakeUpDuration.inHours,
                          minute: _appState.gentleWakeUpDuration.inMinutes % 60,
                        ),
                      ),
                      // As with maxDailyDelta (T-88): the enforced minimum
                      // must not be invisible. The alarm plugin requires a
                      // genuinely positive duration, but the picker allows 00:00.
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          'At least 00:01 h - the alarm stays quiet for this '
                          'long before reaching full volume.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              // FR-20. Belongs here, not in the wake-time group: snooze
              // describes what happens when the alarm rings, not when it
              // rings (the same causal grouping as T-95).
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Snooze",
                      _appState.snoozeEnabled,
                      (value) {
                        // The setter raises `durationToWakeUp` from 00:00 to
                        // 00:10 on switching on - otherwise the budget would
                        // be zero and the feature dead from the start.
                        _appState.snoozeEnabled = value;
                        // The wake time itself changes as a result (FR-2
                        // subtracts `durationToWakeUp`), so a replan is needed.
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
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Snooze never switches the alarm off - it only moves '
                          'it. No QR code needed, even when one is required to '
                          'stop it. Once "Duration to wake up" is used up, '
                          'snoozing stops being offered.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile({required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: child,
      ),
      // color: Theme.of(context).colorScheme.onPrimary,
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

  /// A heading for a group of entries. Without it, the grouping would be
  /// invisible to the user and the order just a different one, not an
  /// explained one (docs/TODO.md T-95). The top spacing is larger than the
  /// spacing between tiles, so the groups visually stand apart.
  Widget _buildSectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 4.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: _appState.accentColor,
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
