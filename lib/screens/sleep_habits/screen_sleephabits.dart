import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/scheduling.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/utils.dart';

// TODO durationToGetReady per weekday - 0x399

class ScreenSleephabits extends StatefulWidget {
  const ScreenSleephabits({super.key});

  @override
  State<ScreenSleephabits> createState() => _ScreenSleephabitsState();
}

class _ScreenSleephabitsState extends State<ScreenSleephabits> {
  late final AppState _appState;
  late final Scheduler _scheduler;

  @override
  void initState() {
    super.initState();
    _scheduler = Scheduler();
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
          // TODO
          _scheduler.scheduleAlarms(_appState);
          break;
        case 'getReady':
          _appState.durationToGetReady = pickedTime;
          // TODO
          _scheduler.scheduleAlarms(_appState);
          break;
        case 'reminder':
          _appState.reminderDuration = pickedTime;
          break;
      }
    }
  }

  void setSleepReminder() {
    try {
      DateTime dateTime;
      try {
        dateTime = Scheduler.nextAlarmTime(_appState);
      } catch (e) {
        debugPrint("=====setSleepReminder: Error getting next alarm time: $e");
        dateTime = DateTime.now();
      }
      try {
        dateTime =
            dateTime.subtract(durationFromTimeOfDay(_appState.sleepGoal));
      } catch (e) {
        debugPrint("=====setSleepReminder: Error subtracting sleepGoal: $e");
        dateTime = dateTime.subtract(const Duration(hours: 8));
      }
      try {
        dateTime = dateTime
            .subtract(durationFromTimeOfDay(_appState.reminderDuration));
      } catch (e) {
        debugPrint(
            "=====setSleepReminder: Error subtracting reminderDuration: $e");
        dateTime = dateTime.subtract(const Duration(minutes: 30));
      }

      try {
        Notifications notifications = Notifications();
        notifications.cancelAllNotifications();
        notifications.scheduleNotification(
            title: 'Sleep time',
            body: "It's time to go to sleep",
            scheduledDate: dateTime);
      } catch (e) {
        debugPrint(
            "=====setSleepReminder: scheduleNotification failed for sleep reminder: $e");
      }
      debugPrint("=====setSleepReminder: Set sleep reminder for $dateTime");
    } catch (e) {
      debugPrint("=====_changeDuration: Error setting sleep reminder: $e");
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
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Duration to wake up"),
                    _buildTimePicker("wakeUp", _appState.durationToWakeUp),
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
              const SizedBox(height: 16.0),
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Enable Reminder",
                      _appState.reminderEnabled,
                      (value) {
                        _appState.reminderEnabled = value;
                        if (_appState.reminderEnabled) {
                          setSleepReminder();
                        }
                      },
                    ),
                    if (_appState.reminderEnabled)
                      _buildTimePicker("reminder", _appState.reminderDuration),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              _buildTile(
                child: _buildToggle(
                  "Gentle WakeUp",
                  _appState.gentleWakeUpEnabled,
                  (value) => _appState.gentleWakeUpEnabled = value,
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

  Widget _buildTimePicker(String setting, TimeOfDay value) {
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
