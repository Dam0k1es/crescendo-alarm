import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/utils/utils.dart';

class ScreenAlarms extends StatefulWidget {
  const ScreenAlarms({super.key});

  // "Scheduled" comes first: the calendar-derived alarms are the actual
  // product path, manual alarms the exception.
  //
  // `const` instead of `static int`: the two used to be mutable and could
  // have been changed from anywhere, even though they describe the tab
  // order below. Whoever swaps these here must also swap the `tabs:` and
  // `TabBarView.children` lists - otherwise the screen shows one list while
  // the button belongs to the other.
  static const int scheduledTabIndex = 0;
  static const int manualTabIndex = 1;

  @override
  State<ScreenAlarms> createState() => _ScreenAlarmsState();
}

class _ScreenAlarmsState extends State<ScreenAlarms>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  late final AppState _appState;

  @override
  bool get wantKeepAlive => true;

  @override
  initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    setState(() {});
  }

  void _addManualAlarm() async {
    var newAlarm = await _showAlarmOverlay(context, null);
    if (newAlarm != null) {
      var result = await _appState.addAlarm(newAlarm);
      bool success = result['success'];
      String errMsg = result['errMsg'];
      if (!success && mounted) {
        displayToast(context, errMsg);
      }
    }
  }

  ListView buildListView(List<MyAlarm> alarms) {
    double bottomPadding = MediaQuery.of(context).size.height * 0.08;

    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: alarms.length,
      itemBuilder: (context, index) {
        return Dismissible(
          key: Key(const Uuid().v4()),
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete),
          ),
          secondaryBackground: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete_forever),
          ),
          onDismissed: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              debugPrint(
                  "=====onDismissed (screen_alarms.list_view): Swiped right. Deleting event with index: $index.");
              await _appState.removeAlarm(alarms[index]);
            } else if (direction == DismissDirection.endToStart) {
              if (_tabController.index == ScreenAlarms.manualTabIndex) {
                debugPrint(
                    "=====onDismissed (screen_alarms.list_view): Swiped left. Deleting all events in manual tab.");
                await _appState.removeAllAlarms(true, false);
              }
              if (_tabController.index == ScreenAlarms.scheduledTabIndex) {
                debugPrint(
                    "=====onDismissed (screen_alarms.list_view): Swiped left. Deleting all events in scheduled tab.");
                await _appState.removeAllAlarms(false, true);
              }
            }
          },
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.endToStart) {
              return await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text("Confirmation"),
                    content: const Text(
                        "Do you really want to delete all elements?"),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text("Delete"),
                      ),
                    ],
                  );
                },
              );
            }
            return true;
          },
          child: GestureDetector(
            onTap: () => _editAlarm(alarms[index]),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.alarm,
                    color: context.watch<AppState>().accentColor),
                title: Text(
                  formatTimeOfDay(TimeOfDay(
                      hour: alarms[index].time.hour,
                      minute: alarms[index].time.minute)),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 44,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      alarms[index].title,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(
                        fontSize: 18,
                      ),
                    ),
                    // User request: always show which day(s) a manual alarm
                    // rings on, at a glance, without opening the edit
                    // dialog. Scheduled alarms have no `repeatOnDays` of
                    // their own - each is a single calendar-derived day - so
                    // this is manual-only.
                    if (alarms[index] case final ManualAlarm manualAlarm)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: _buildWeekdayPills(context, manualAlarm),
                      ),
                  ],
                ),
                trailing: Switch(
                  value: alarms[index].enabled,
                  onChanged: (bool value) async {
                    final alarm = alarms[index];
                    if (alarm is ScheduledAlarm) {
                      // FR-21 (docs/TODO.md T-03): for a planned alarm the
                      // toggle is a statement about the DAY, not about the
                      // object - otherwise the next re-plan would overwrite
                      // it, because FR-18 rebuilds the alarm set every time.
                      setState(() => alarm.enabled = value);
                      _appState.setDayEnabled(isoDate(alarm.time), value);
                      runCheckpointSafely(_appState,
                          trigger: CheckpointTrigger.settingsChanged);
                      return;
                    }
                    // FR-21, manual alarms: the object itself is the durable
                    // statement, but it only counts once the platform has
                    // accepted it. A refused call leaves the switch where it
                    // was - the alarm would still ring, and the switch must
                    // not claim otherwise.
                    final messenger = ScaffoldMessenger.of(context);
                    final applied = await _appState.setManualAlarmEnabled(
                        alarm as ManualAlarm, value);
                    if (!mounted) return;
                    setState(() {});
                    if (!applied) {
                      // The messenger was taken before the await, so no
                      // BuildContext crosses the gap.
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Could not change this alarm'),
                        duration: Duration(seconds: 5),
                        persist: false,
                      ));
                    }
                  },
                  activeThumbColor: context
                      .watch<AppState>()
                      .accentColor
                      .withValues(alpha: 0.05),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
        title: const Text(
          'Alarms',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Phase 6 (docs/TODO.md T-64/FR-11): switching tabs replans NOTHING.
        // It used to kick off the old Scheduler, which in doing so could
        // delete all planned alarms and abort with no replacement. Calendar
        // changes deliberately have no trigger of their own (FR-11) - they
        // take effect at the next checkpoint, which opening the app triggers
        // anyway (FR-17).
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
          indicatorColor: context.watch<AppState>().accentColor,
          tabs: [
            Tab(
              icon: Icon(Icons.calendar_month,
                  color: context.watch<AppState>().accentColor),
              text: "Scheduled",
            ),
            Tab(
              icon: Icon(Icons.access_alarm,
                  color: context.watch<AppState>().accentColor),
              text: "Manual",
            ),
          ],
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              buildListView(appState.scheduledAlarms),
              buildListView(appState.manualAlarms),
            ],
          );
        },
      ),
      floatingActionButton: _tabController.index == ScreenAlarms.manualTabIndex
          ? FloatingActionButton(
              tooltip: 'Add A New Alarm',
              backgroundColor: Theme.of(context).colorScheme.surface,
              onPressed: () => _addManualAlarm(),
              child:
                  Icon(Icons.add, color: context.watch<AppState>().accentColor),
            )
          : FloatingActionButton(
              tooltip: 'Sync Alarms',
              backgroundColor: Theme.of(context).colorScheme.surface,
              // The explicit user action "reconcile now" - deliberately
              // bypasses FR-17's daily lock (Phase 6, T-64: the old
              // Scheduler used to run here).
              onPressed: () => runCheckpointSafely(_appState,
                  trigger: CheckpointTrigger.manualSync),
              child: Icon(Icons.sync,
                  color: context.watch<AppState>().accentColor),
            ),
    );
  }

  void _editAlarm(MyAlarm oldAlarm) async {
    if (oldAlarm is ScheduledAlarm) {
      const message = "Can not edit scheduled alarms!";
      displayToast(context, message);
      return;
    }
    ManualAlarm? updatedAlarm =
        await _showAlarmOverlay(context, oldAlarm as ManualAlarm);
    if (updatedAlarm != null) {
      var result = await _appState.updateAlarm(oldAlarm, updatedAlarm);
      bool success = result['success'];
      String errMsg = result['errMsg'];
      if (!success && mounted) {
        displayToast(context, errMsg);
      }
    }
  }

  Future<ManualAlarm?> _showAlarmOverlay(
      BuildContext context, ManualAlarm? alarm) async {
    TextEditingController titleController =
        TextEditingController(text: alarm?.title ?? 'Alarm');
    titleController.addListener(() {
      alarm?.title = titleController.text;
    });
    bool gentleWake = alarm?.gentlewake ?? _appState.gentleWakeUpEnabled;
    // docs/TODO.md T-96: the same pre-filling as for gentlewake, volume, and
    // tone alongside it. Without it, a manual alarm would stubbornly use
    // MyAlarm's default of one minute and ignore the user's setting - the
    // bug class from T-84 (a setting with a UI that never reaches the alarm).
    Duration gentleWakeDuration =
        alarm?.gentleWakeDuration ?? _appState.gentleWakeUpDuration;
    double volume = alarm?.volume ?? _appState.selectedVolume;
    // docs/TODO.md T-50: same inheritance rule as the others above.
    bool vibrate = alarm?.vibrate ?? _appState.vibrationEnabled;
    String selectedTone = alarm?.tone ?? _appState.selectedTone;
    DateTime nowDT = DateTime.now().add(const Duration(minutes: 1));
    TimeOfDay nowTOD = TimeOfDay(hour: nowDT.hour, minute: nowDT.minute);
    TimeOfDay pickedTime = alarm?.time ?? nowTOD;

    // Initialize repeatOnDays with the current day selected by default
    DateTime now = DateTime.now();
    DayOfWeek currentDay = DayOfWeek.values[now.weekday - 1];

    Map<DayOfWeek, bool> repeatOnDays = {
      DayOfWeek.monday: alarm?.repeatOnDays[DayOfWeek.monday] ??
          (currentDay == DayOfWeek.monday),
      DayOfWeek.tuesday: alarm?.repeatOnDays[DayOfWeek.tuesday] ??
          (currentDay == DayOfWeek.tuesday),
      DayOfWeek.wednesday: alarm?.repeatOnDays[DayOfWeek.wednesday] ??
          (currentDay == DayOfWeek.wednesday),
      DayOfWeek.thursday: alarm?.repeatOnDays[DayOfWeek.thursday] ??
          (currentDay == DayOfWeek.thursday),
      DayOfWeek.friday: alarm?.repeatOnDays[DayOfWeek.friday] ??
          (currentDay == DayOfWeek.friday),
      DayOfWeek.saturday: alarm?.repeatOnDays[DayOfWeek.saturday] ??
          (currentDay == DayOfWeek.saturday),
      DayOfWeek.sunday: alarm?.repeatOnDays[DayOfWeek.sunday] ??
          (currentDay == DayOfWeek.sunday),
    };

    return showDialog<ManualAlarm>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Center(
                  child: Text(alarm == null ? 'Add Alarm' : 'Edit Alarm')),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: TextButton(
                            child: Text(
                              formatTimeOfDay(pickedTime),
                              style: const TextStyle(
                                fontSize: 32,
                              ),
                            ),
                            onPressed: () async {
                              TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialEntryMode: TimePickerEntryMode.dial,
                                  initialTime: pickedTime,
                                  builder:
                                      (BuildContext context, Widget? child) {
                                    return MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                            alwaysUse24HourFormat: true),
                                        child: Theme(
                                          data: ThemeData.light().copyWith(
                                            colorScheme: ColorScheme.light(
                                              primary: _appState.accentColor,
                                              onPrimary: Colors.white,
                                              surface: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              onSurface: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            dialogTheme: DialogThemeData(
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                            ),
                                          ),
                                          child: child ?? const Text(''),
                                        ));
                                  });
                              if (picked != null) {
                                setState(() {
                                  pickedTime = picked;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Edit Title
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            labelStyle: TextStyle(fontSize: 20),
                          ),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Gentle Wake Up
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Gentle Wake Up',
                                style: TextStyle(fontSize: 20)),
                            Switch(
                              value: gentleWake,
                              onChanged: (value) {
                                setState(() {
                                  gentleWake = value;
                                });
                              },
                              activeThumbColor: _appState.accentColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Set Alarm Tone
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tone', style: TextStyle(fontSize: 20)),
                            const SizedBox(height: 8),
                            DropdownButton<String>(
                              isExpanded: true,
                              // Make the dropdown button as wide as its parent
                              value: selectedTone,
                              onChanged: (String? newValue) {
                                setState(() {
                                  selectedTone = newValue!;
                                });
                              },
                              // TODO source tones dynamic instead of static list - 0x55
                              items: [
                                _buildDropdownItem(context, 'Annoying Alarm',
                                    'assets/sounds/annoying_alarm.mp3'),
                                _buildDropdownItem(context, 'LolliPop',
                                    'assets/sounds/lollipop.mp3'),
                                _buildDropdownItem(context, 'Old Telephone',
                                    'assets/sounds/old_telephone_ring.mp3'),
                                _buildDropdownItem(context, 'Wake UP',
                                    'assets/sounds/wake_up.mp3'),
                                _buildDropdownItem(context, 'WakeyWakey',
                                    'assets/sounds/wakeywakey.mp3'),
                                _buildDropdownItem(context, 'WakeyWakey 2',
                                    'assets/sounds/wakeywakey2.mp3'),
                                // Only offered once the user has imported one
                                // (Settings > Alarm Tones) - there is nothing
                                // to select otherwise.
                                if (_appState.customTonePath != null)
                                  _buildDropdownItem(context, 'Custom Tone',
                                      _appState.customTonePath!),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Set Volume
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Volume',
                                style: TextStyle(fontSize: 20)),
                            Slider(
                              value: volume,
                              onChanged: (value) {
                                setState(() {
                                  volume = value;
                                });
                              },
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              activeColor: _appState.accentColor,
                              label: '${(volume * 100).round()}%',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Set repeatOnDays
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          children: [
                            for (var day in [
                              DayOfWeek.monday,
                              DayOfWeek.tuesday,
                              DayOfWeek.wednesday,
                              DayOfWeek.thursday,
                              DayOfWeek.friday
                            ])
                              _buildDaySelector(
                                  context, day, repeatOnDays, setState),
                            const SizedBox(width: double.infinity),
                            for (var day in [
                              DayOfWeek.saturday,
                              DayOfWeek.sunday
                            ])
                              _buildDaySelector(
                                  context, day, repeatOnDays, setState),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel', style: TextStyle(fontSize: 20)),
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                ),
                TextButton(
                  child: const Text('Save', style: TextStyle(fontSize: 20)),
                  onPressed: () {
                    Navigator.of(context).pop(ManualAlarm(
                      id: alarm?.id ?? getRandom(),
                      time: pickedTime,
                      title: titleController.text,
                      enabled: alarm?.enabled ?? true,
                      gentlewake: gentleWake,
                      gentleWakeDuration: gentleWakeDuration,
                      tone: selectedTone,
                      repeatOnDays: repeatOnDays,
                      volume: volume,
                      vibrate: vibrate,
                    ));
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  DropdownMenuItem<String> _buildDropdownItem(
      BuildContext context, String label, String value) {
    return DropdownMenuItem<String>(
      value: value,
      child: Text(
        label,
        style: const TextStyle(fontSize: 20),
      ),
    );
  }
}

/// User request: a small, read-only pill per weekday on the alarm list
/// itself, so which day(s) a manual alarm rings on is visible without
/// opening the edit dialog - the same information [_buildDaySelector]
/// already lets the user set, just not shown anywhere outside that dialog
/// before now.
Widget _buildWeekdayPills(BuildContext context, ManualAlarm alarm) {
  final accent = context.watch<AppState>().accentColor;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final day in DayOfWeek.values)
        Padding(
          padding: const EdgeInsets.only(right: 4.0),
          child: CircleAvatar(
            radius: 10,
            backgroundColor: (alarm.repeatOnDays[day] ?? false)
                ? accent
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              // The full two-letter label, not just its first letter:
              // Tuesday/Thursday and Saturday/Sunday would otherwise both
              // read as the same single letter.
              _getDayLabel(day),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: (alarm.repeatOnDays[day] ?? false)
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _buildDaySelector(BuildContext context, DayOfWeek day,
    Map<DayOfWeek, bool> repeatOnDays, StateSetter setState) {
  String dayLabel = _getDayLabel(day);
  return GestureDetector(
    onTap: () {
      setState(() {
        repeatOnDays[day] = !repeatOnDays[day]!;
      });
    },
    child: CircleAvatar(
      radius: 20,
      backgroundColor: repeatOnDays[day]!
          ? context.watch<AppState>().accentColor
          : Colors.white,
      child: Text(
        dayLabel,
        style: TextStyle(
          color: repeatOnDays[day]! ? Colors.white : Colors.black,
          fontSize: 16,
        ),
      ),
    ),
  );
}

// Repository hygiene pass (2026-09): these were German abbreviations
// ("DIE"/Dienstag, "MI"/Mittwoch, "DO"/Donnerstag, "SA"/Samstag,
// "SO"/Sonntag) shown directly in the UI, missed by the earlier audit
// because none of them are full German words. Now English throughout,
// matching the project's standing "everything in English" rule.
String _getDayLabel(DayOfWeek day) {
  switch (day) {
    case DayOfWeek.monday:
      return "Mo";
    case DayOfWeek.tuesday:
      return "Tu";
    case DayOfWeek.wednesday:
      return "We";
    case DayOfWeek.thursday:
      return "Th";
    case DayOfWeek.friday:
      return "Fr";
    case DayOfWeek.saturday:
      return "Sa";
    case DayOfWeek.sunday:
      return "Su";
  }
}
