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
        // docs/TODO.md T-72: ohne diese beiden Regler waren FR-4s Drift, FR-7s
        // Teil-Kappung und FR-10s wunschzeit-Zweig für Nutzer unerreichbar -
        // wunschzeit war immer null, maxDailyDelta immer das Minimum.
        case 'wunschzeit':
          _appState.wunschzeit = pickedTime;
          break;
        case 'maxDailyDelta':
          _appState.maxDailyDelta =
              Duration(hours: pickedTime.hour, minutes: pickedTime.minute);
          break;
        // docs/TODO.md T-96: wie lange die Gentle-Wake-Rampe braucht, also wie
        // lange der Alarm leise bleibt. War vorher festverdrahtet.
        // FR-20: um wie viel ein Druck auf Snooze verschiebt.
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
              // Drei ursaechliche Gruppen (docs/TODO.md T-95). Die vorherige
              // Reihenfolge fuehrte in die Irre: "Sleep Goal" stand oben,
              // beeinflusst aber die Alarmzeit gar nicht - es verschiebt nur
              // die Bettgeh-Erinnerung - und war von "Enable Reminder", seiner
              // anderen Haelfte derselben Rechnung, durch drei fremde
              // Eintraege getrennt.
              _buildSectionHeader("Wake-up time"),
              // Zuerst das Ziel, auf das FR-4 zudriftet: die einzige
              // Einstellung, die ein Nutzer ohne Kalendertermine ueberhaupt
              // braucht.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Preferred wake-up time",
                      _appState.wunschzeit != null,
                      (value) {
                        if (value) {
                          _appState.wunschzeit =
                              _appState.wunschzeit ?? const TimeOfDay(hour: 7, minute: 0);
                        } else {
                          _appState.wunschzeit = null;
                        }
                        runCheckpointSafely(_appState,
                            trigger: CheckpointTrigger.settingsChanged);
                      },
                    ),
                    if (_appState.wunschzeit != null)
                      _buildTimePicker("wunschzeit", _appState.wunschzeit!,
                          isDuration: false),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              // Direkt darunter die Schranke, wie schnell sich die Weckzeit
              // diesem Ziel naehern darf (FR-6) - sie qualifiziert den Eintrag
              // darueber und ist ohne ihn sinnlos.
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
                    // docs/TODO.md T-88: AppState klemmt diesen Wert nach unten
                    // auf 15 Minuten (sonst käme die Glättung praktisch nie
                    // voran). Das war für den Nutzer unsichtbar - wer 5
                    // Minuten wählte, bekam stillschweigend 15.
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
              // Dann die zwei Vorlaufzeiten. Sie greifen nur an Tagen MIT
              // Termin (FR-2) und stehen deshalb nach dem Ziel - in der
              // Reihenfolge, in der sie real anfallen und in der `hardFloor`
              // sie abzieht: erst aufwachen, dann fertig werden.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Duration to wake up"),
                    _buildTimePicker("wakeUp", _appState.durationToWakeUp),
                    // FR-20: dieselbe Dauer ist das Snooze-Budget. Der
                    // Zusammenhang ist nicht zu erraten, also steht er da -
                    // aber nur, wenn Snooze ueberhaupt an ist.
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
              // Das Schlafziel definiert die Bettzeit
              // (Weckzeit - sleepGoal - reminderDuration, siehe
              // lib/utils/sleep_reminder.dart) und beruehrt die Alarmzeit
              // NICHT. Deshalb hier und nicht in der Gruppe darueber.
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
              // Der Vorlauf misst sich von der Bettzeit aus, die der Eintrag
              // darueber festlegt - beide gehoeren nebeneinander.
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Enable Reminder",
                      _appState.reminderEnabled,
                      (value) {
                        _appState.reminderEnabled = value;
                        // FR-16 "Voraussetzung": scheduled unconditionally -
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
                        // docs/TODO.md T-84: siehe Ton/Lautstärke - gentlewake
                        // ist eine Eigenschaft der bereits gesetzten Alarme.
                        runCheckpointSafely(_appState,
                            trigger: CheckpointTrigger.settingsChanged);
                      },
                    ),
                    // docs/TODO.md T-96: nur sichtbar, wenn Gentle Wake an ist -
                    // ohne die Rampe hat die Dauer keine Bedeutung. Gleiches
                    // Muster wie beim Reminder-Schalter darueber.
                    if (_appState.gentleWakeUpEnabled) ...[
                      _buildLabel("Ramp duration"),
                      _buildTimePicker(
                        "gentleWakeDuration",
                        TimeOfDay(
                          hour: _appState.gentleWakeUpDuration.inHours,
                          minute: _appState.gentleWakeUpDuration.inMinutes % 60,
                        ),
                      ),
                      // Wie bei maxDailyDelta (T-88): das erzwungene Minimum
                      // darf nicht unsichtbar sein. Das Alarm-Plugin verlangt
                      // eine echt positive Dauer, der Picker laesst aber 00:00 zu.
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
              // FR-20. Gehoert hierher und nicht zur Weckzeit-Gruppe: Snooze
              // beschreibt, was beim Klingeln passiert, nicht wann geklingelt
              // wird (dieselbe kausale Gruppierung wie T-95).
              _buildTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      "Snooze",
                      _appState.snoozeEnabled,
                      (value) {
                        // Der Setter hebt `durationToWakeUp` beim Einschalten
                        // von 00:00 auf 00:10 - sonst waere das Budget null
                        // und die Funktion von Anfang an tot.
                        _appState.snoozeEnabled = value;
                        // Die Weckzeit selbst aendert sich dadurch (FR-2 zieht
                        // `durationToWakeUp` ab), also muss neu geplant werden.
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

  /// [isDuration] entscheidet über das Suffix: die meisten Regler hier sind
  /// Zeitspannen ("01:30 h"), die gewünschte Weckzeit (FR-3) ist dagegen eine
  /// Uhrzeit und wurde vom geteilten Picker fälschlich als Dauer beschriftet
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

  /// Ueberschrift einer Eintragsgruppe. Ohne sie waere die Gruppierung fuer
  /// den Nutzer unsichtbar und die Reihenfolge nur eine andere, keine
  /// erklaerte (docs/TODO.md T-95). Der Abstand oben ist groesser als der
  /// zwischen den Kacheln, damit die Gruppen optisch auseinandertreten.
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
