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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/models/alarms/custom_tone.dart' as custom_tone;
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm_enable.dart';
import 'package:crescendo_alarm/models/alarms/myalarm.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/models/scheduling/next_wake_up.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/utils/direct_boot_mirror.dart' as direct_boot_mirror;
import 'package:crescendo_alarm/utils/utils.dart';

class AppState extends ChangeNotifier {
  late final SharedPreferences _prefs;
  late final Future<void> initialized;

  // General variables
  int _currentPageIndex = 0;

  // Alarms Screen variables
  List<ManualAlarm> _manualAlarms = [];
  List<ScheduledAlarm> _scheduledAlarms = [];

  // Schedule Screen variables
  String _currentTimeZone = '';
  bool _calendarsInitialized = false;
  List<DateTime> _fetchedCalendarWeeks = [];
  List<Meeting> _meetings = [];
  DateTime _visibleDate =
      DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  // Scan Code Screen variables
  DeactivationCode? _deactivationCode;

  // Sleep Goal Configuration variables
  TimeOfDay _sleepGoal = const TimeOfDay(hour: 8, minute: 0);
  // FR-20: default 00:15 (maintainer request) - snooze is on by default
  // (see _snoozeEnabled below), so a real wake-up budget out of the box
  // makes more sense than 00:00. If a user explicitly drives it down to
  // 00:00 while snooze is on, it still gets raised to 00:10 when snooze is
  // (re-)switched on - see the snoozeEnabled setter.
  TimeOfDay _durationToWakeUp = const TimeOfDay(hour: 0, minute: 15);
  Set<String> _disabledDays = <String>{};

  /// Calendar events (by their `device_calendar` id, `Meeting.ids`) the user
  /// has chosen to leave out of scheduling - a feature request, not an FR:
  /// some appointments (on a shared calendar the user doesn't own, or just
  /// not worth waking up for) should not drive `hardFloor`, but marking that
  /// must never write back to the calendar itself. Keyed by id, not by the
  /// `Meeting` value, so a later sync's freshly-constructed `Meeting` for the
  /// same real-world appointment is still recognised.
  Set<String> _ignoredEventIds = <String>{};

  // docs/TODO.md T-53: which `device_calendar` calendars (by `Calendar.id`,
  // never a name - regularly the user's own email address for a Google/
  // Exchange account) are left out of both the Schedule display and
  // scheduling. Stores what's explicitly DESELECTED, not what's selected -
  // an empty set means every calendar counts, which is every existing
  // install's current behaviour, and a calendar the device adds later (never
  // seen before, so absent from this set either way) is included by default
  // rather than silently dropped until the user notices and opts it in.
  Set<String> _deselectedCalendarIds = <String>{};
  // Default on, per maintainer request - snooze is the common case, not an
  // opt-in most users would otherwise never discover.
  bool _snoozeEnabled = true;
  Duration _snoozeTime = const Duration(minutes: 5);
  Map<int, DateTime> _snoozeOriginOf = <int, DateTime>{};
  TimeOfDay _durationToGetReady = const TimeOfDay(hour: 0, minute: 45);
  // docs/TODO.md T-52.3: absent from this map means "use the global
  // _durationToGetReady value for that day" - so an empty map (the default,
  // matching every existing install) behaves exactly as before. A day gets
  // its own value only once the user explicitly overrides it.
  Map<DayOfWeek, TimeOfDay> _durationToGetReadyByWeekday =
      <DayOfWeek, TimeOfDay>{};

  // docs/TODO.md T-52.1: FR-4's drift/hold behaviour on a day with no
  // calendar entry of its own is the only thing scheduling-v2 ever did on
  // such a day - `true` here reproduces exactly that (every existing
  // install's current behaviour); `false` opts out and leaves those days
  // with no alarm planned at all.
  bool _scheduleOnGapDays = true;

  bool _reminderEnabled = false;
  TimeOfDay _reminderDuration = const TimeOfDay(hour: 0, minute: 30);
  // Default on with a 5-minute ramp, per maintainer request.
  bool _gentleWakeUpEnabled = true;
  Duration _gentleWakeUpDuration = const Duration(minutes: 5);

  // Scheduling-v2 variables (docs/scheduling-v2-spec.md FR-3/FR-9/FR-16/FR-17)
  int _gapDayCounter = 0;
  int _lastCheckedUtcOffsetMinutes = 0;
  DateTime? _lastReplanDate;
  DateTime? _lastProcessedConcludedDay;
  Map<String, int?> _pendingDayValues = {};
  Map<String, bool> _pendingDayInstantAnchored = {};
  bool _overrunNotificationSent = false;
  bool _safetyValveNotificationSent = false;
  bool _diagnosticsEnabled = true;
  bool _diagnosticsIncludeClockTimes = false;
  TimeOfDay? _preferredWakeUpTime;
  // Default 1 hour, per maintainer request - the enforced minimum below is
  // unchanged (15 minutes), this only raises the out-of-the-box starting
  // point.
  Duration _maxDailyDelta = const Duration(hours: 1);

  static const _maxDailyDeltaMinimum = Duration(minutes: 15);

  /// docs/TODO.md T-96: the alarm plugin has `assert(fadeDuration > Duration.zero)`
  /// (`VolumeSettings.fade`), and the hh:mm picker on the sleep-habits screen
  /// allows 00:00. Assertions are off in the release build, so a zero would
  /// reach it unchecked - hence a hard lower bound. One minute is also the
  /// value that was hardcoded before T-96.
  static const _gentleWakeUpDurationMinimum = Duration(minutes: 1);

  // Theming variables
  bool _darkMode = false;

  /// docs/TODO.md T-51: whether the theme should follow the OS setting
  /// instead of [_darkMode]'s manual value. Kept as a separate flag, not a
  /// tri-state replacement of [_darkMode] itself, so switching it back off
  /// restores the user's manual choice instead of losing it - see
  /// [themeMode]'s own doc comment. Default on, per maintainer request.
  bool _followSystemTheme = true;
  Color _accentColor = Colors.blue;

  // Alarm tone and volume variables
  String _selectedTone = 'assets/sounds/lollipop.mp3';
  double _selectedVolume = 0.8;

  /// docs/TODO.md T-50: the default new alarms inherit (mirroring
  /// `selectedVolume`/`selectedTone`) - `true` to match the previously
  /// hardcoded behaviour, since this setting didn't exist before.
  bool _vibrationEnabled = true;

  /// The user's own imported tones (docs/TODO.md T-56) - each a name plus a
  /// path relative to the app's Documents directory (see `custom_tone.dart`'s
  /// doc comment for why a path, not a reference to the picked file), empty
  /// until at least one has been imported. Distinct from
  /// [_selectedTone]/a `MyAlarm.tone`, which may or may not point at one of
  /// these: importing a tone doesn't select it anywhere by itself.
  List<custom_tone.CustomTone> _customTones = [];

  // State variables
  bool _permissionsGranted = false;
  bool _isReadingCalendarMutex = false;
  bool _firstUpdateOfCalendar = true;

  /// docs/TODO.md T-45: how `SharedPreferences.getInstance()` itself is
  /// obtained is injectable purely for testability - the same pattern as
  /// `documentsDirectory`/`fetchEvents`/`now` elsewhere in this class - so a
  /// throwing plugin can be simulated without a platform channel.
  final Future<SharedPreferences> Function() _getPrefsInstance;

  AppState({Future<SharedPreferences> Function()? getPrefsInstance})
      : _getPrefsInstance = getPrefsInstance ?? SharedPreferences.getInstance {
    initialized = _loadFromPreferences();
  }

  // Getter
  int get currentPageIndex => _currentPageIndex;

  DeactivationCode? get deactivationCode => _deactivationCode;

  bool get reminderEnabled => _reminderEnabled;

  bool get gentleWakeUpEnabled => _gentleWakeUpEnabled;

  /// How long the gentle-wake ramp takes to reach full volume - i.e. how
  /// long the alarm stays quiet (docs/TODO.md T-96).
  Duration get gentleWakeUpDuration => _gentleWakeUpDuration;

  bool get calendarsInitialized => _calendarsInitialized;

  bool get firstUpdateOfCalendar => _firstUpdateOfCalendar;

  bool get darkMode => _darkMode;

  bool get followSystemTheme => _followSystemTheme;

  /// docs/TODO.md T-51: the one thing `MyApp.build` actually needs -
  /// combining [followSystemTheme] and [darkMode] into the `ThemeMode`
  /// Flutter's `MaterialApp` takes, computed here so main.dart can't drift
  /// from this by re-deriving it itself (the same "one source of truth"
  /// reasoning as every other computed value in this project).
  ThemeMode get themeMode {
    if (_followSystemTheme) return ThemeMode.system;
    return _darkMode ? ThemeMode.dark : ThemeMode.light;
  }

  TimeOfDay get sleepGoal => _sleepGoal;

  TimeOfDay get durationToWakeUp => _durationToWakeUp;

  /// FR-21: days (as `isoDate`) for which the user has switched off the
  /// planned alarm. Deliberately beside `pendingDayValues`, not inside it:
  /// there, `null` would mean "nothing planned", and the next planning run
  /// would overwrite the entry out of its own arithmetic - the user's veto
  /// would vanish with it.
  Set<String> get disabledDays => _disabledDays;

  bool isDayDisabled(String isoDay) => _disabledDays.contains(isoDay);

  void setDayEnabled(String isoDay, bool enabled) {
    if (enabled ? !_disabledDays.contains(isoDay) : _disabledDays.contains(isoDay)) {
      return;
    }
    _disabledDays = enabled
        ? ({..._disabledDays}..remove(isoDay))
        : {..._disabledDays, isoDay};
    _prefs.setStringList('disabledDays', _disabledDays.toList()..sort());
    notifyListeners();
  }

  /// FR-21 + docs/TODO.md T-82: the same retention bound as for the planned
  /// values - otherwise the set grows without limit.
  void pruneDisabledDays(String oldestKeptDay) {
    final kept = _disabledDays.where((d) => d.compareTo(oldestKeptDay) >= 0).toSet();
    if (kept.length == _disabledDays.length) return;
    _disabledDays = kept;
    _prefs.setStringList('disabledDays', _disabledDays.toList()..sort());
  }

  /// The raw set of ignored `device_calendar` event ids - never the
  /// `Meeting` objects themselves, so ignoring an event can never write
  /// anything back to the calendar (which may not even belong to the user).
  Set<String> get ignoredEventIds => _ignoredEventIds;

  bool isEventIgnored(Meeting meeting) =>
      meeting.ids.any(_ignoredEventIds.contains);

  void setEventIgnored(Meeting meeting, bool ignored) {
    if (ignored == isEventIgnored(meeting)) return;
    final updated = {..._ignoredEventIds};
    if (ignored) {
      updated.addAll(meeting.ids);
    } else {
      updated.removeAll(meeting.ids);
    }
    _ignoredEventIds = updated;
    _prefs.setStringList('ignoredEventIds', _ignoredEventIds.toList()..sort());
    notifyListeners();
  }

  /// docs/TODO.md T-53: the raw set of deselected calendar ids - see
  /// [_deselectedCalendarIds]'s own doc comment for why absence, not
  /// presence, is what's persisted.
  Set<String> get deselectedCalendarIds => _deselectedCalendarIds;

  bool isCalendarSelected(String calendarId) =>
      !_deselectedCalendarIds.contains(calendarId);

  void setCalendarSelected(String calendarId, bool selected) {
    if (selected == isCalendarSelected(calendarId)) return;
    final updated = {..._deselectedCalendarIds};
    if (selected) {
      updated.remove(calendarId);
    } else {
      updated.add(calendarId);
    }
    _deselectedCalendarIds = updated;
    _prefs.setStringList(
        'deselectedCalendarIds', _deselectedCalendarIds.toList()..sort());
    notifyListeners();
  }

  /// FR-20: may the user postpone the alarm? Default **off**.
  bool get snoozeEnabled => _snoozeEnabled;

  /// FR-20: by how much pressing snooze postpones. Default 5 minutes.
  Duration get snoozeTime => _snoozeTime;

  /// FR-20: the **original** wake instant of a call currently postponed.
  /// Carries the remaining budget across several snoozes and across a
  /// process death - without it, the user would have the full budget again
  /// after a restart, and snooze would be unbounded.
  DateTime? snoozeOriginFor(int alarmId) => _snoozeOriginOf[alarmId];

  void rememberSnoozeOrigin(int alarmId, DateTime originalRing) {
    if (_snoozeOriginOf.containsKey(alarmId)) return; // only the FIRST call counts
    _snoozeOriginOf = {..._snoozeOriginOf, alarmId: originalRing};
    _saveSnoozeOrigins();
    notifyListeners();
  }

  void forgetSnoozeOrigin(int alarmId) {
    if (!_snoozeOriginOf.containsKey(alarmId)) return;
    _snoozeOriginOf = {..._snoozeOriginOf}..remove(alarmId);
    _saveSnoozeOrigins();
    notifyListeners();
  }

  void _saveSnoozeOrigins() => _prefs.setString(
      'snoozeOriginOf',
      jsonEncode(_snoozeOriginOf
          .map((id, at) => MapEntry('$id', at.millisecondsSinceEpoch))));

  TimeOfDay get durationToGetReady => _durationToGetReady;

  // docs/TODO.md T-52.3: a read-only view of the overrides - the alarm
  // editor/replan side should always resolve through
  // [durationToGetReadyForWeekday], never read this map directly, or a day
  // without an override would wrongly look unset instead of falling back to
  // the global value.
  Map<DayOfWeek, TimeOfDay> get durationToGetReadyByWeekday =>
      Map.unmodifiable(_durationToGetReadyByWeekday);

  TimeOfDay durationToGetReadyForWeekday(DayOfWeek day) =>
      _durationToGetReadyByWeekday[day] ?? _durationToGetReady;

  bool get scheduleOnGapDays => _scheduleOnGapDays;

  TimeOfDay get reminderDuration => _reminderDuration;

  DateTime get visibleDate => _visibleDate;

  List<Meeting> get meetings => _meetings;

  List<DateTime> get fetchedCalendarWeeks => _fetchedCalendarWeeks;

  List<ManualAlarm> get manualAlarms => _manualAlarms;

  // Scheduling-v2 (docs/scheduling-v2-spec.md FR-3/FR-9/FR-16/FR-17)
  int get gapDayCounter => _gapDayCounter;

  Duration get lastCheckedUtcOffset =>
      Duration(minutes: _lastCheckedUtcOffsetMinutes);

  /// FR-17's daily guard **only**: "has a checkpoint already run today?".
  /// Deliberately no longer doubles as the day-advance progress marker - see
  /// [lastProcessedConcludedDay] (`docs/TODO.md` T-75).
  DateTime? get lastReplanDate => _lastReplanDate;

  /// The last calendar day that has actually been *concluded and processed* by
  /// a replan - i.e. counted by FR-9's `gapDayCounter` and checked by FR-12.
  ///
  /// Split out from [lastReplanDate] (`docs/TODO.md` T-75): since T-71 the day
  /// a replan may treat as concluded depends on its trigger (the ring
  /// checkpoint concludes today, FR-17's recovery and a settings change do
  /// not), while "a checkpoint ran today" is true for all of them. Sharing one
  /// field meant a perfectly normal early-morning recovery replan consumed the
  /// marker without advancing it, and the real ring later that day then found
  /// nothing left to process - that day was lost for good, so FR-9 under-counted
  /// (its safety valve could never trip) and FR-12 never reported for it.
  DateTime? get lastProcessedConcludedDay => _lastProcessedConcludedDay;

  /// Raw `ISO date -> millisecondsSinceEpoch|null` map, deliberately kept in
  /// this exact shape (not e.g. `Map<DateTime, DateTime?>`) because FR-16
  /// Checkpoint 2 reads/writes the same `SharedPreferences` key from a
  /// background isolate with no `AppState`/`Provider` access at all - the
  /// stored format must be decodable without any AppState-side model.
  Map<String, int?> get pendingDayValues => _pendingDayValues;

  /// Per planned day: was its value taken directly from a real `hardFloor`
  /// (`true`, instant-anchored - a fixed real moment) or computed from
  /// `preferredWakeUpTime`/the smoothing curve (`false`, wall-clock-anchored)? FR-16's
  /// Checkpoint 2 runs in a background isolate without calendar access and
  /// cannot re-derive this, so it is persisted next to [pendingDayValues] in
  /// the same directly-decodable shape.
  Map<String, bool> get pendingDayInstantAnchored => _pendingDayInstantAnchored;

  /// FR-6 requires the overrun warning "einmalig" - remembers that it was
  /// already sent for the currently running overrun episode
  /// (`docs/TODO.md` T-74a).
  bool get overrunNotificationSent => _overrunNotificationSent;

  /// FR-9's counterpart to [overrunNotificationSent] (`docs/TODO.md` T-81):
  /// the safety-valve warning had no such throttle, while
  /// `safetyValveTriggered` is re-derived by `computeWeekPlan` on *every*
  /// replan - so the warning repeated on every app open and every settings
  /// change for as long as the valve stayed engaged. Which, before T-78, was
  /// forever: with no alarms left there is no ring checkpoint to reset it.
  bool get safetyValveNotificationSent => _safetyValveNotificationSent;

  /// Whether the PII-free event logger records (`docs/TODO.md` T-89).
  ///
  /// On by default: the log only ever leaves the device when the user
  /// explicitly copies it in settings, and it structurally cannot contain
  /// personal data - the recording API takes not a single String. The
  /// switch exists anyway, because "on, but switchable off and inspectable"
  /// is the only honest default.
  bool get diagnosticsEnabled => _diagnosticsEnabled;

  /// Does the log also record wake times and early appointment times
  /// (`docs/TODO.md` T-135)? Default **off**, and deliberately separate from
  /// [diagnosticsEnabled].
  ///
  /// The rest of the log is structurally free of personal data - there is
  /// no String parameter and no clock value, so no channel either. A
  /// history of wake times and earliest appointment times, by contrast, is
  /// a sleep pattern with a daily routine, identifying with no name at all.
  /// And the log is explicitly exportable via the clipboard - a user who
  /// attaches it to a bug report would send that along too. Hence
  /// explicitly opt-in, and deliberately not folded into the general
  /// diagnostics toggle.
  bool get diagnosticsIncludeClockTimes => _diagnosticsIncludeClockTimes;

  TimeOfDay? get preferredWakeUpTime => _preferredWakeUpTime;

  Duration get maxDailyDelta => _maxDailyDelta;

  List<ScheduledAlarm> get scheduledAlarms => _scheduledAlarms;

  Color get accentColor => _accentColor;

  bool get isReadingCalendarMutex => _isReadingCalendarMutex;

  String get currentTimeZone => _currentTimeZone;

  bool get permissionsGranted => _permissionsGranted;

  String get selectedTone => _selectedTone;

  double get selectedVolume => _selectedVolume;

  bool get vibrationEnabled => _vibrationEnabled;

  List<custom_tone.CustomTone> get customTones =>
      List.unmodifiable(_customTones);

  // Setter
  //
  // Repository hygiene pass (2026-09): this used to also persist the index
  // via `_prefs.setInt('currentPageIndex', ...)`, but the matching load on
  // startup was commented out (dead code), so every launch reset to tab 0
  // regardless - the write was pure unread disk I/O on every tab switch.
  // Removed rather than restoring the load: always opening on the first tab
  // is a deliberate, common choice, not an oversight to silently change here.
  set currentPageIndex(int index) {
    _currentPageIndex = index;
    notifyListeners();
  }

  set deactivationCode(DeactivationCode? deactivationCode) {
    _deactivationCode = deactivationCode;
    final encodedCode = jsonEncode(_deactivationCode);
    _prefs.setString('deactivationCode', encodedCode);
    notifyListeners();
  }

  set reminderEnabled(bool value) {
    _reminderEnabled = value;
    _prefs.setBool('reminderEnabled', _reminderEnabled);
    notifyListeners();
  }

  set gentleWakeUpEnabled(bool value) {
    _gentleWakeUpEnabled = value;
    _prefs.setBool('gentleWakeUpEnabled', _gentleWakeUpEnabled);
    notifyListeners();
  }

  set gentleWakeUpDuration(Duration value) {
    // Bounded below (docs/TODO.md T-96): the alarm plugin requires
    // `fadeDuration > Duration.zero`, but the hh:mm picker allows 00:00 -
    // and in the release build the assertion wouldn't fire anyway.
    _gentleWakeUpDuration =
        value < _gentleWakeUpDurationMinimum ? _gentleWakeUpDurationMinimum : value;
    _prefs.setInt('gentleWakeUpSeconds', _gentleWakeUpDuration.inSeconds);
    notifyListeners();
  }





  set gapDayCounter(int value) {
    _gapDayCounter = value;
    _prefs.setInt('gapDayCounter', _gapDayCounter);
    notifyListeners();
  }

  set lastCheckedUtcOffset(Duration value) {
    _lastCheckedUtcOffsetMinutes = value.inMinutes;
    _prefs.setInt(
        'lastCheckedUtcOffsetMinutes', _lastCheckedUtcOffsetMinutes);
    notifyListeners();
  }

  set lastReplanDate(DateTime? value) {
    _lastReplanDate = value;
    if (value == null) {
      _prefs.remove('lastReplanDate');
    } else {
      _prefs.setString('lastReplanDate', value.toIso8601String());
    }
    notifyListeners();
  }

  set lastProcessedConcludedDay(DateTime? value) {
    _lastProcessedConcludedDay = value;
    if (value == null) {
      _prefs.remove('lastProcessedConcludedDay');
    } else {
      _prefs.setString('lastProcessedConcludedDay', value.toIso8601String());
    }
    notifyListeners();
  }

  set pendingDayValues(Map<String, int?> value) {
    _pendingDayValues = value;
    _prefs.setString('pendingDayValues', jsonEncode(value));
    notifyListeners();
  }

  set pendingDayInstantAnchored(Map<String, bool> value) {
    _pendingDayInstantAnchored = value;
    _prefs.setString('pendingDayInstantAnchored', jsonEncode(value));
    notifyListeners();
  }

  set diagnosticsIncludeClockTimes(bool value) {
    _diagnosticsIncludeClockTimes = value;
    _prefs.setBool('diagnosticsIncludeClockTimes', value);
    Diag.setIncludeClockTimes(value);
    notifyListeners();
  }

  set diagnosticsEnabled(bool value) {
    _diagnosticsEnabled = value;
    _prefs.setBool('diagnosticsEnabled', _diagnosticsEnabled);
    Diag.setEnabled(value);
    notifyListeners();
  }

  set safetyValveNotificationSent(bool value) {
    _safetyValveNotificationSent = value;
    _prefs.setBool('safetyValveNotificationSent', _safetyValveNotificationSent);
    notifyListeners();
  }

  set overrunNotificationSent(bool value) {
    _overrunNotificationSent = value;
    _prefs.setBool('overrunNotificationSent', _overrunNotificationSent);
    notifyListeners();
  }

  set preferredWakeUpTime(TimeOfDay? value) {
    _preferredWakeUpTime = value;
    if (value == null) {
      // The stored key was renamed from 'preferredWakeUpTime' along with the
      // identifier. That drops the setting of anyone who upgrades from an
      // older build, because nothing reads the old key any more. The
      // maintainer accepted this explicitly while the app is still in its
      // test phase - no production users exist yet. Once it ships, a key
      // rename needs a fallback read of the old key instead.
      _prefs.remove('preferredWakeUpTime');
    } else {
      _prefs.setString('preferredWakeUpTime', '${value.hour}:${value.minute}');
    }
    notifyListeners();
  }

  set maxDailyDelta(Duration value) {
    _maxDailyDelta =
        value < _maxDailyDeltaMinimum ? _maxDailyDeltaMinimum : value;
    _prefs.setInt('maxDailyDeltaMinutes', _maxDailyDelta.inMinutes);
    notifyListeners();
  }

  set sleepGoal(TimeOfDay value) {
    _sleepGoal = value;
    _prefs.setString('sleepGoal', '${_sleepGoal.hour}:${_sleepGoal.minute}');
    notifyListeners();
  }

  /// FR-20. If snooze is switched on while [durationToWakeUp] is `00:00`,
  /// it's raised to 10 minutes: otherwise the budget would be zero and the
  /// feature just switched on would be dead from the start. A value already
  /// set is left untouched - and switching off resets nothing, so a brief
  /// off period doesn't lose the setting.
  set snoozeEnabled(bool value) {
    _snoozeEnabled = value;
    _prefs.setBool('snoozeEnabled', value);
    if (value &&
        _durationToWakeUp.hour == 0 &&
        _durationToWakeUp.minute == 0) {
      durationToWakeUp = const TimeOfDay(hour: 0, minute: 10);
    }
    notifyListeners();
  }

  set snoozeTime(Duration value) {
    _snoozeTime = value;
    _prefs.setInt('snoozeTimeMinutes', value.inMinutes);
    notifyListeners();
  }

  set durationToWakeUp(TimeOfDay value) {
    _durationToWakeUp = value;
    _prefs.setString('durationToWakeUp',
        '${_durationToWakeUp.hour}:${_durationToWakeUp.minute}');
    notifyListeners();
  }


  set durationToGetReady(TimeOfDay value) {
    _durationToGetReady = value;
    _prefs.setString('durationToGetReady',
        '${_durationToGetReady.hour}:${_durationToGetReady.minute}');
    notifyListeners();
  }

  /// docs/TODO.md T-52.3: sets (or, with `value == null`, clears) this one
  /// day's override. Clearing rather than setting it back to the global
  /// value keeps the day following the global setting if that is changed
  /// again later, instead of freezing it at whatever the global value
  /// happened to be at the time.
  void setDurationToGetReadyForWeekday(DayOfWeek day, TimeOfDay? value) {
    if (value == null) {
      _durationToGetReadyByWeekday.remove(day);
    } else {
      _durationToGetReadyByWeekday[day] = value;
    }
    _prefs.setString(
        'durationToGetReadyByWeekday',
        jsonEncode(_durationToGetReadyByWeekday
            .map((day, time) => MapEntry(day.toString(), '${time.hour}:${time.minute}'))));
    notifyListeners();
  }

  set scheduleOnGapDays(bool value) {
    _scheduleOnGapDays = value;
    _prefs.setBool('scheduleOnGapDays', _scheduleOnGapDays);
    notifyListeners();
  }

  set reminderDuration(TimeOfDay value) {
    _reminderDuration = value;
    _prefs.setString('reminderDuration',
        '${_reminderDuration.hour}:${_reminderDuration.minute}');
    notifyListeners();
  }

  set scheduledAlarms(List<ScheduledAlarm> alarms) {
    _scheduledAlarms = alarms;
    notifyListeners();
  }

  /// docs/TODO.md T-141: the "assign and persist" half of pruning stale
  /// `ScheduledAlarm`s - the retention policy itself
  /// (`pruneScheduledAlarms`) lives in `apply_alarms.dart`, not here, so this
  /// class doesn't have to import scheduling code and break the one-way
  /// layering every other scheduling file already depends on (they import
  /// `AppState`, never the reverse).
  void setPrunedScheduledAlarms(List<ScheduledAlarm> alarms) {
    if (listEquals(alarms, _scheduledAlarms)) return;
    _scheduledAlarms = alarms;
    _saveScheduledAlarms();
    notifyListeners();
  }

  set visibleDate(DateTime value) {
    _visibleDate = value;
    // Must not persist
    notifyListeners();
  }

  set meetings(List<Meeting> value) {
    _meetings = value;
    // Must not persist
    notifyListeners();
  }

  set fetchedCalendarWeeks(List<DateTime> dateTime) {
    _fetchedCalendarWeeks = dateTime;
    // Must not persist
    notifyListeners();
  }

  set calendarsInitialized(bool value) {
    _calendarsInitialized = value;
    // Must not persist
    notifyListeners();
  }

  set firstUpdateOfCalendar(bool value) {
    _firstUpdateOfCalendar = value;
    // Must not persist
    notifyListeners();
  }

  set currentTimeZone(String value) {
    _currentTimeZone = value;
    // Must not persist
    notifyListeners();
  }

  set darkMode(bool value) {
    _darkMode = value;
    _prefs.setBool('darkMode', _darkMode);
    notifyListeners();
  }

  set followSystemTheme(bool value) {
    _followSystemTheme = value;
    _prefs.setBool('followSystemTheme', _followSystemTheme);
    notifyListeners();
  }

  set accentColor(Color color) {
    _accentColor = color;
    _prefs.setInt('accentColor', color.toARGB32());
    notifyListeners();
  }

  set isReadingCalendarMutex(bool value) {
    _isReadingCalendarMutex = value;
    // No persistence needed
    notifyListeners();
  }


  set permissionsGranted(bool value) {
    _permissionsGranted = value;
    _prefs.setBool('permissionsGranted', _permissionsGranted);
    notifyListeners();
  }

  set selectedTone(String value) {
    _selectedTone = value;
    _prefs.setString('selectedTone', _selectedTone);
    notifyListeners();
  }

  set selectedVolume(double value) {
    _selectedVolume = value;
    _prefs.setDouble('selectedVolume', _selectedVolume);
    notifyListeners();
  }

  set vibrationEnabled(bool value) {
    _vibrationEnabled = value;
    _prefs.setBool('vibrationEnabled', _vibrationEnabled);
    notifyListeners();
  }

  /// Copies [sourcePath] (wherever the system file picker pointed at) into
  /// the app's own storage and adds it to [customTones] under [name] - see
  /// `custom_tone.dart`'s doc comment for why a copy, not a reference.
  ///
  /// docs/TODO.md T-56: appends, never replaces - every previously imported
  /// tone stays selectable. [name] is the picker UI's job to collect (it
  /// pre-fills a dialog with `defaultCustomToneName(sourcePath)` but lets the
  /// user change it), not this method's - by the time this is called, the
  /// name is already decided.
  ///
  /// [documentsDirectory] is injected for testability (the same pattern as
  /// `fetchEvents`/`now` elsewhere in this class): production code leaves it
  /// unset and gets the real directory from `path_provider`, tests pass a
  /// temporary one instead of needing a platform channel.
  ///
  /// Rethrows [UnsupportedToneFormatException] for a file type the alarm
  /// plugin's player can't be relied on to play - the caller (the picker UI)
  /// is expected to catch it and tell the user, rather than this model layer
  /// reaching into `BuildContext` to do so itself.
  Future<custom_tone.CustomTone> addCustomTone(
    String sourcePath, {
    required String name,
    Future<Directory> Function()? documentsDirectory,
  }) async {
    final dir = await (documentsDirectory ?? getApplicationDocumentsDirectory)();
    final relativePath = await custom_tone.importCustomTone(
      sourcePath: sourcePath,
      documentsDirectory: dir,
    );
    final tone = custom_tone.CustomTone(name: name, path: relativePath);
    _customTones = [..._customTones, tone];
    _saveCustomTones();
    notifyListeners();
    return tone;
  }

  void _saveCustomTones() {
    final encoded = jsonEncode(_customTones.map((t) => t.toJson()).toList());
    _prefs.setString('customTones', encoded);
  }

  List<custom_tone.CustomTone>? _loadCustomTones() {
    try {
      final encoded = _prefs.getString('customTones');
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .map((e) =>
              custom_tone.CustomTone.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint("=====_loadCustomTones: Error loading customTones: ${e.runtimeType}");
      return null;
    }
  }

  Future<Map<String, dynamic>> addAlarm(MyAlarm alarm) async {
    var retVal = {
      'success': false,
      'errMsg': 'Default Error Message. This should not happen!',
    };

    if (alarm is ManualAlarm) {
      // Fetch a DateTime, as ManualAlarms use TimeOfDay
      DateTime alarmDateTime = _getAlarmTime(alarm);
      // Create a new alarm in case it was set to a DayTime in the past
      ManualAlarm newAlarm = ManualAlarm(
          id: alarm.id,
          time:
              TimeOfDay(hour: alarmDateTime.hour, minute: alarmDateTime.minute),
          title: alarm.title,
          enabled: alarm.enabled,
          gentlewake: alarm.gentlewake,
          gentleWakeDuration: alarm.gentleWakeDuration,
          tone: alarm.tone,
          volume: alarm.volume,
          vibrate: alarm.vibrate,
          repeatOnDays: alarm.repeatOnDays);
      if (_manualAlarms.contains(alarm)) {
        debugPrint(
            'ManualAlarm with id ${alarm.id} is already in list! Removing it.');
        _manualAlarms.remove(alarm);
      }
      _manualAlarms.add(newAlarm);
      _manualAlarms.sort((x, y) => compareTimeOfDay(x.time, y.time));
      _saveManualAlarms();
      retVal = {
        'success': true,
        'errMsg': '',
      };
      // FR-21 (docs/TODO.md T-03): a switched-off alarm is never armed - not
      // when it is created and not when it is edited. Without this guard the
      // defect returns through the back door: the user changes the title of a
      // switched-off alarm and it is live again.
      if (newAlarm.enabled) {
        await _setAlarm(newAlarm, alarmDateTime);
      }
    } else if (alarm is ScheduledAlarm) {
      // Create a new alarm in case it was set to a DayTime in the past
      ScheduledAlarm newAlarm = ScheduledAlarm(
          id: alarm.id,
          time: alarm.time,
          enabled: alarm.enabled,
          gentlewake: alarm.gentlewake,
          gentleWakeDuration: alarm.gentleWakeDuration,
          tone: alarm.tone,
          volume: alarm.volume,
          vibrate: alarm.vibrate);
      if (_scheduledAlarms.contains(alarm)) {
        debugPrint(
            'ScheduledAlarm with id ${alarm.id} is already in list! Removing it.');
        _scheduledAlarms.remove(alarm);
      }
      if (!alarm.time.isBefore(DateTime.now())) {
        _scheduledAlarms.add(newAlarm);
        _scheduledAlarms.sort((x, y) => x.time.compareTo(y.time));
        _saveScheduledAlarms();
        retVal = {
          'success': true,
          'errMsg': '',
        };
        await _setAlarm(newAlarm, alarm.time);
      }
    }

    notifyListeners();
    return retVal;
  }

  Future<Map<String, dynamic>> updateAlarm(
      MyAlarm oldAlarm, MyAlarm newAlarm) async {
    if (oldAlarm is ManualAlarm) {
      debugPrint(
          "=====updateAlarm: Updating alarm settings for ${oldAlarm.time}");
      int index = _manualAlarms.indexOf(oldAlarm);
      if (index != -1) {
        // Set a new id for the alarm as the alarm library may fail to set an alarm with the same id directly after stopping it
        newAlarm.id = getRandom();
        // Set the new alarm in the list of custom alarm data type
        _manualAlarms[index] = newAlarm as ManualAlarm;
        _saveManualAlarms();
        // Set the new alarm in the list of flutter_alarm plugin type
        DateTime alarmDateTime = _getAlarmTime(newAlarm);
        // FR-21: see addAlarm - editing must not arm a switched-off alarm.
        if (newAlarm.enabled) {
          await _setAlarm(newAlarm, alarmDateTime);
        }
        await removeAlarm(oldAlarm);
        notifyListeners();
        return {'success': true, 'errMsg': ''};
      }
    } else {
      debugPrint(
          "=====updateAlarm: The alarm ${oldAlarm.id} is not of type ManualAlarm: ${oldAlarm.runtimeType}");
    }

    return {'success': false, 'errMsg': 'Alarm not found'};
  }

  Future<void> removeAlarm(MyAlarm alarm) async {
    if (alarm is ManualAlarm) {
      _manualAlarms.remove(alarm);
      _saveManualAlarms();
    } else {
      _scheduledAlarms.remove(alarm);
      _saveScheduledAlarms();
    }

    await _stopAlarm(alarm.id);
    notifyListeners();
  }

  Future<void> removeAllAlarms(bool manualAlarms, bool scheduledAlarms) async {
    if (manualAlarms) {
      List<ManualAlarm> alarmsCopy = List.from(_manualAlarms);
      for (ManualAlarm alarm in alarmsCopy) {
        await removeAlarm(alarm);
      }
    }
    if (scheduledAlarms) {
      List<ScheduledAlarm> alarmsCopy = List.from(_scheduledAlarms);
      for (ScheduledAlarm alarm in alarmsCopy) {
        await removeAlarm(alarm);
      }
    }
  }

  MyAlarm? getAlarm(int id) {
    debugPrint("=====getAlarm: Searching for alarm with id $id");
    try {
      for (MyAlarm alarm in _manualAlarms) {
        if (alarm.id == id) {
          return alarm;
        }
      }
    } catch (e) {
      debugPrint("=====getAlarm: ${e.runtimeType}");
    }
    try {
      for (MyAlarm alarm in _scheduledAlarms) {
        if (alarm.id == id) {
          return alarm;
        }
      }
    } catch (e) {
      debugPrint("=====getAlarm: ${e.runtimeType}");
    }
    return null;
  }

  /// Resolves a [ManualAlarm]'s bare [TimeOfDay] to its next occurrence.
  ///
  /// Only [ManualAlarm]s: a `ScheduledAlarm` already carries an absolute
  /// instant and is handed straight to `_setAlarm`, which converts it properly
  /// (`alarmPlatformTime`). The former `ScheduledAlarm` branch here was
  /// unreachable - both call sites sit inside a `ManualAlarm` check - **and** a
  /// latent T-61 trap: it rebuilt `DateTime(alarm.time.year, ...)` from the
  /// instant's raw fields, reinterpreting UTC digits as device-local time.
  /// Deleted rather than fixed (docs/TODO.md T-86).
  DateTime _getAlarmTime(ManualAlarm alarm) {
    debugPrint(
        "=====getAlarmTime: ${alarm.id} is a manual alarm set on ${alarm.time}");
    // The resolution itself lives in manual_alarm_enable.dart, so that
    // re-arming through the FR-21 toggle uses exactly this rule and cannot
    // drift away from it (a duplicate would be a silent off-by-one-day).
    return nextManualOccurrence(alarm.time, DateTime.now(), alarm.repeatOnDays);
  }

  /// FR-21 (docs/TODO.md T-03): makes the alarm-list toggle of a manual alarm
  /// real - it cancels the armed platform alarm or arms it again.
  ///
  /// Returns `false` when the platform refused; nothing is then changed or
  /// persisted, because the flag has to keep describing what the device will
  /// actually do.
  Future<bool> setManualAlarmEnabled(ManualAlarm alarm, bool enabled) async {
    final applied = await applyManualAlarmEnabled(
      alarm: alarm,
      enabled: enabled,
      now: DateTime.now(),
      armAlarm: _setAlarm,
      stopAlarm: _stopAlarm,
    );
    if (!applied) return false;

    _saveManualAlarms();
    notifyListeners();
    return true;
  }

  Future<void> _setAlarm(MyAlarm alarm, DateTime alarmDateTime) async {
    final alarmSettings = buildRingingAlarmSettings(
      id: alarm.id,
      // docs/TODO.md T-61: converts the instant to local time first instead of
      // reinterpreting its raw digits as local (see alarmPlatformTime).
      dateTime: alarmPlatformTime(alarmDateTime),
      tone: alarm.tone,
      gentlewake: alarm.gentlewake,
      volume: alarm.volume,
      gentleWakeDuration: alarm.gentleWakeDuration,
      title: alarm.title,
      body: "Your alarm is ringing",
      vibrate: alarm.vibrate,
    );

    // Set the alarm
    await Alarm.set(alarmSettings: alarmSettings);
    refreshDirectBootFallback();
  }

  /// FR-20: arms the **postponed** wake call as a plain platform alarm.
  ///
  /// Deliberately with no entry in [scheduledAlarms] or [manualAlarms]:
  /// FR-18 removes every `ScheduledAlarm` in the future with no planned
  /// counterpart, and a postponed call has none. A platform entry the app
  /// doesn't track as its own alarm, by contrast, is left untouched (T-127).
  ///
  /// Tone, volume, and ramp come from the current settings - the postponed
  /// call should sound like the one it replaces.
  Future<void> setSnoozeAlarm(int id, DateTime at) async {
    await Alarm.set(
      alarmSettings: buildRingingAlarmSettings(
        id: id,
        dateTime: alarmPlatformTime(at),
        tone: _selectedTone,
        gentlewake: _gentleWakeUpEnabled,
        volume: _selectedVolume,
        gentleWakeDuration: _gentleWakeUpDuration,
        title: 'Snoozed alarm',
        body: "Your alarm is ringing",
        vibrate: _vibrationEnabled,
      ),
    );
  }

  Future<void> stopPlatformAlarm(int id) => _stopAlarm(id);

  Future<void> _stopAlarm(int id) async {
    await Alarm.stop(id);
    refreshDirectBootFallback();
  }

  /// docs/TODO.md T-158: recomputes the next moment a real alarm is
  /// expected to ring - the same instant [nextWakeUpTime] already computes
  /// for the bedtime reminder (T-66) - and mirrors it into Android's
  /// device-protected storage via [direct_boot_mirror.mirrorDirectBootFallback].
  ///
  /// Called after every successful [_setAlarm]/[_stopAlarm], which together
  /// are the one place every real arm/cancel already goes through (manual
  /// alarm create/edit/toggle, and scheduling-v2's own sync via
  /// `applyPlannedAlarms`'s `addAlarm`/`removeAlarm`) - so this stays
  /// current without a second, easy-to-miss call site at every UI or
  /// scheduling entry point. Also called once after loading persisted state
  /// at app start, so upgrading from a version that predates this mirror
  /// populates it immediately rather than waiting for the next alarm change.
  ///
  /// Deliberately NOT called from [setSnoozeAlarm]: a snoozed instant isn't
  /// part of [pendingDayValues] or [manualAlarms], so [nextWakeUpTime]
  /// cannot see it - a reboot during an active snooze is not covered by
  /// this mirror. Narrow, not silent: this is a known gap, not an oversight
  /// (see docs/TODO.md T-158).
  ///
  /// [now] is injectable purely for testability, the same as elsewhere in
  /// this file - fire-and-forget (not awaited by callers) since a failed or
  /// slow mirror must never block a real arm/cancel.
  void refreshDirectBootFallback({DateTime Function()? now}) {
    final nowFn = now ?? DateTime.now;
    unawaited(direct_boot_mirror.mirrorDirectBootFallback(nextWakeUpTime(
      pendingDayValues: _pendingDayValues,
      manualAlarms: _manualAlarms,
      now: nowFn(),
    )));
  }

  void _saveScheduledAlarms() {
    final encodedAlarms = jsonEncode(_scheduledAlarms);
    _prefs.setString('scheduled_alarms', encodedAlarms);
  }

  void _saveManualAlarms() {
    final encodedAlarms = jsonEncode(_manualAlarms);
    _prefs.setString('manual_alarms', encodedAlarms);
  }

  List<ScheduledAlarm>? _loadScheduledAlarms() {
    try {
      final encodedAlarms = _prefs.getString('scheduled_alarms');
      if (encodedAlarms == null) return null;

      final decodedAlarms = (jsonDecode(encodedAlarms) as List)
          .map((alarmMap) => ScheduledAlarm.fromJson(alarmMap))
          .toList();
      return decodedAlarms;
    } catch (e) {
      debugPrint(
          "=====_loadScheduledAlarms: Error loading scheduled alarms: ${e.runtimeType}");
      return null;
    }
  }

  List<ManualAlarm>? _loadManualAlarms() {
    try {
      final encodedAlarms = _prefs.getString('manual_alarms');
      if (encodedAlarms == null) return null;

      final decodedAlarms = (jsonDecode(encodedAlarms) as List)
          .map((alarmMap) => ManualAlarm.fromJson(alarmMap))
          .toList();
      return decodedAlarms;
    } catch (e) {
      debugPrint("=====_loadManualAlarms: Error loading manual alarms: ${e.runtimeType}");
      return null;
    }
  }

  DateTime? _loadStoredDate(String key) {
    try {
      final data = _prefs.getString(key);
      if (data == null) return null;
      return DateTime.parse(data);
    } catch (e) {
      debugPrint("=====_loadStoredDate: Error loading $key: ${e.runtimeType}");
      return null;
    }
  }

  DateTime? _loadLastReplanDate() => _loadStoredDate('lastReplanDate');

  /// FR-20. Malformed or old data leads to an empty map, never a startup
  /// abort - the same posture as the other loaded fields (docs/TODO.md
  /// T-45).
  Map<int, DateTime> _loadSnoozeOrigins() {
    try {
      final raw = _prefs.getString('snoozeOriginOf');
      if (raw == null) return <int, DateTime>{};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((id, millis) => MapEntry(
          int.parse(id), DateTime.fromMillisecondsSinceEpoch(millis as int)));
    } catch (e) {
      debugPrint("=====_loadSnoozeOrigins: ${e.runtimeType}");
      return <int, DateTime>{};
    }
  }

  /// docs/TODO.md T-75. Falls back to the old `lastReplanDate` key when the
  /// new one is absent: on an app that was installed before the two markers
  /// were split, `lastReplanDate` *was* the day-advance progress marker, so
  /// reusing it here is the correct migration - starting the new field at
  /// `null` instead would make the next replan re-process (and re-count, FR-9)
  /// a day that had already concluded.
  DateTime? _loadLastProcessedConcludedDay() =>
      _loadStoredDate('lastProcessedConcludedDay') ?? _loadLastReplanDate();

  Map<String, int?>? _loadPendingDayValues() {
    try {
      final data = _prefs.getString('pendingDayValues');
      if (data == null) return null;
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as int?));
    } catch (e) {
      debugPrint(
          "=====_loadPendingDayValues: Error loading pendingDayValues: ${e.runtimeType}");
      return null;
    }
  }

  TimeOfDay? _loadPreferredWakeUpTime() {
    try {
      final data = _prefs.getString('preferredWakeUpTime');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint("=====_loadPreferredWakeUpTime: Error loading preferredWakeUpTime: ${e.runtimeType}");
      return null;
    }
  }

  Map<String, bool>? _loadPendingDayInstantAnchored() {
    try {
      final data = _prefs.getString('pendingDayInstantAnchored');
      if (data == null) return null;
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as bool));
    } catch (e) {
      debugPrint(
          "=====_loadPendingDayInstantAnchored: Error loading pendingDayInstantAnchored: ${e.runtimeType}");
      return null;
    }
  }

  DeactivationCode? _loadDeactivationCode() {
    try {
      final encodedDeactivationCode = _prefs.getString('deactivationCode');
      if (encodedDeactivationCode == 'null' ||
          encodedDeactivationCode == null) {
        return null;
      }

      final decodedDeactivationCode =
          DeactivationCode.fromJson(jsonDecode(encodedDeactivationCode));
      return decodedDeactivationCode;
    } catch (e) {
      debugPrint(
          "=====_loadDeactivationCode: Error loading deactivation code: ${e.runtimeType}");
      return null;
    }
  }

  TimeOfDay? _loadSleepGoal() {
    try {
      final data = _prefs.getString('sleepGoal');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint("=====_loadSleepGoal: Error loading sleep goal: ${e.runtimeType}");
      return null;
    }
  }

  TimeOfDay? _loadDurationToWakeUp() {
    try {
      final data = _prefs.getString('durationToWakeUp');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint(
          "=====_loadDurationToWakeUp: Error loading durationToWakeUp: ${e.runtimeType}");
      return null;
    }
  }


  TimeOfDay? _loadDurationToGetReady() {
    try {
      final data = _prefs.getString('durationToGetReady');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint(
          "=====_loadDurationToGetReady: Error loading durationToGetReady: ${e.runtimeType}");
      return null;
    }
  }

  Map<DayOfWeek, TimeOfDay>? _loadDurationToGetReadyByWeekday() {
    try {
      final data = _prefs.getString('durationToGetReadyByWeekday');
      if (data == null) return null;
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      return decoded.map((dayName, time) => MapEntry(
          DayOfWeek.values.firstWhere((d) => d.toString() == dayName),
          timeOfDayFromString(time as String)));
    } catch (e) {
      debugPrint(
          "=====_loadDurationToGetReadyByWeekday: Error loading durationToGetReadyByWeekday: ${e.runtimeType}");
      return null;
    }
  }

  TimeOfDay? _loadReminderDuration() {
    try {
      final data = _prefs.getString('reminderDuration');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint(
          "=====_loadReminderDuration: Error loading reminderDuration: ${e.runtimeType}");
      return null;
    }
  }

  /// docs/TODO.md T-55: `fetchedCalendarWeeks` records each preloaded week by
  /// its *start* (see `preloadCalendarData`, `lib/utils/utils.dart`), but
  /// [dateTime] here is typically an arbitrary day within a week (e.g.
  /// "today"). Comparing [dateTime] itself against those start-of-week
  /// entries used to only match on the rare day that happened to already be
  /// Monday - every other day reported its already-preloaded week as not
  /// fetched, triggering a redundant fetch that duplicated the week's
  /// calendar entries. Normalizing [dateTime] to its own start of week first
  /// makes the comparison apples-to-apples.
  ///
  /// docs/TODO.md T-42: the week is always normalized to Monday - there used
  /// to be a `startOfWeekDay` setting gating this subtraction, but it had no
  /// UI and, even set, never changed the *target* day the correction landed
  /// on (always Monday regardless), only whether the correction ran at all -
  /// a no-op distinction, since `Duration(days: 0)` is already a no-op when
  /// [dateTime] is already Monday. Removed rather than wired up to a UI
  /// nobody asked for.
  Future<bool> isCalendarWeekFetched(DateTime dateTime) async {
    DateTime startOfWeek =
        dateTime.subtract(Duration(days: dateTime.weekday - 1));
    DateTime dateOnly =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    try {
      for (DateTime fetchedDate in _fetchedCalendarWeeks) {
        if (fetchedDate.year == dateOnly.year &&
            fetchedDate.month == dateOnly.month &&
            fetchedDate.day == dateOnly.day) {
          debugPrint(
              "=====isCalendarWeekFetched: $dateTime has been fetched. (See $_fetchedCalendarWeeks)");
          return true;
        }
      }
    } catch (e) {
      debugPrint("=====isCalendarWeekFetched: ${e.runtimeType}");
      return false;
    }

    debugPrint(
        "=====isCalendarWeekFetched: $dateTime has not been fetched. (See $_fetchedCalendarWeeks)");
    return false;
  }

  /// docs/TODO.md T-69: re-reads the scheduling-v2 fields that FR-16's
  /// Checkpoint 2 may have written straight to `SharedPreferences` from a
  /// background isolate, where this (main-isolate) instance never saw the
  /// change. Called at the start of every `replan()` so a plan is never merged
  /// on top of a stale in-memory copy.
  Future<void> reloadSchedulingStateFromPreferences() async {
    try {
      await _prefs.reload();
      _gapDayCounter = _prefs.getInt('gapDayCounter') ?? _gapDayCounter;
      _lastCheckedUtcOffsetMinutes =
          _prefs.getInt('lastCheckedUtcOffsetMinutes') ??
              _lastCheckedUtcOffsetMinutes;
      _lastReplanDate = _loadLastReplanDate() ?? _lastReplanDate;
      _lastProcessedConcludedDay =
          _loadLastProcessedConcludedDay() ?? _lastProcessedConcludedDay;
      _pendingDayValues = _loadPendingDayValues() ?? _pendingDayValues;
      _pendingDayInstantAnchored =
          _loadPendingDayInstantAnchored() ?? _pendingDayInstantAnchored;
    } catch (e) {
      debugPrint(
          "=====reloadSchedulingStateFromPreferences: Error reloading: ${e.runtimeType}");
    }
  }

  // only overrides values not being already set
  Future<void> _loadFromPreferences() async {
    // docs/TODO.md T-45: this call used to sit outside every try block below,
    // so a throwing plugin (a platform-channel failure, corrupted storage)
    // propagated straight out of this method - which `initialized` exposes
    // and which main() awaits before runApp(), blocking the app from
    // starting at all. For an alarm clock that means every already-armed
    // platform alarm becomes unreachable: no checkpoint runs, no dismiss
    // screen shows, nothing. Its own try, separate from the settings-loading
    // one below: `_prefs` staying unassigned here is exactly the condition
    // that try's own `LateInitializationError` catch degrades gracefully
    // from, so nothing further needs to change to make that fallback take
    // effect - only this line needed to stop escaping unguarded.
    try {
      _prefs = await _getPrefsInstance();
    } catch (e) {
      debugPrint(
          "=====_loadFromPreferences: Error obtaining SharedPreferences instance: ${e.runtimeType}");
    }
    // A failure below must never leave _prefs unassigned or throw out of
    // this method: main() awaits `initialized` before runApp(), so any
    // unhandled error here would prevent the app from starting at all.
    // Corrupted or incompatible persisted data should fall back to defaults
    // instead of crashing the app on launch.
    try {
      _permissionsGranted =
          _prefs.getBool('permissionsGranted') ?? _permissionsGranted;
      _reminderEnabled = _prefs.getBool('reminderEnabled') ?? _reminderEnabled;
      _gentleWakeUpEnabled =
          _prefs.getBool('gentleWakeUpEnabled') ?? _gentleWakeUpEnabled;
      final gentleWakeUpSeconds = _prefs.getInt('gentleWakeUpSeconds');
      if (gentleWakeUpSeconds != null) {
        _gentleWakeUpDuration = Duration(seconds: gentleWakeUpSeconds);
      }
      _sleepGoal = _loadSleepGoal() ?? _sleepGoal;
      _durationToWakeUp = _loadDurationToWakeUp() ?? _durationToWakeUp;
      _durationToGetReady = _loadDurationToGetReady() ?? _durationToGetReady;
      _durationToGetReadyByWeekday = _loadDurationToGetReadyByWeekday() ??
          _durationToGetReadyByWeekday;
      _scheduleOnGapDays =
          _prefs.getBool('scheduleOnGapDays') ?? _scheduleOnGapDays;
      _reminderDuration = _loadReminderDuration() ?? _reminderDuration;
      _scheduledAlarms = _loadScheduledAlarms() ?? _scheduledAlarms;
      _manualAlarms = _loadManualAlarms() ?? _manualAlarms;
      _selectedTone = _prefs.getString('selectedTone') ?? _selectedTone;
      _customTones = _loadCustomTones() ?? _customTones;
      _selectedVolume = _prefs.getDouble('selectedVolume') ?? _selectedVolume;
      _vibrationEnabled =
          _prefs.getBool('vibrationEnabled') ?? _vibrationEnabled;
      _darkMode = _prefs.getBool('darkMode') ?? _darkMode;
      _followSystemTheme =
          _prefs.getBool('followSystemTheme') ?? _followSystemTheme;
      _accentColor =
          Color(_prefs.getInt('accentColor') ?? _accentColor.toARGB32());
      _deactivationCode = _loadDeactivationCode();
      _gapDayCounter = _prefs.getInt('gapDayCounter') ?? _gapDayCounter;
      _lastCheckedUtcOffsetMinutes =
          _prefs.getInt('lastCheckedUtcOffsetMinutes') ??
              _lastCheckedUtcOffsetMinutes;
      _lastReplanDate = _loadLastReplanDate() ?? _lastReplanDate;
      _lastProcessedConcludedDay =
          _loadLastProcessedConcludedDay() ?? _lastProcessedConcludedDay;
      _pendingDayValues = _loadPendingDayValues() ?? _pendingDayValues;
      _pendingDayInstantAnchored =
          _loadPendingDayInstantAnchored() ?? _pendingDayInstantAnchored;
      _overrunNotificationSent =
          _prefs.getBool('overrunNotificationSent') ?? _overrunNotificationSent;
      _safetyValveNotificationSent =
          _prefs.getBool('safetyValveNotificationSent') ??
              _safetyValveNotificationSent;
      _diagnosticsEnabled =
          _prefs.getBool('diagnosticsEnabled') ?? _diagnosticsEnabled;
      _disabledDays =
          (_prefs.getStringList('disabledDays') ?? const <String>[]).toSet();
      _ignoredEventIds =
          (_prefs.getStringList('ignoredEventIds') ?? const <String>[]).toSet();
      _deselectedCalendarIds = (_prefs.getStringList('deselectedCalendarIds') ??
              const <String>[])
          .toSet();
      _snoozeEnabled = _prefs.getBool('snoozeEnabled') ?? _snoozeEnabled;
      final snoozeMinutes = _prefs.getInt('snoozeTimeMinutes');
      if (snoozeMinutes != null) _snoozeTime = Duration(minutes: snoozeMinutes);
      _snoozeOriginOf = _loadSnoozeOrigins();
      _diagnosticsIncludeClockTimes =
          _prefs.getBool('diagnosticsIncludeClockTimes') ??
              _diagnosticsIncludeClockTimes;
      _preferredWakeUpTime = _loadPreferredWakeUpTime();
      final maxDailyDeltaMinutes = _prefs.getInt('maxDailyDeltaMinutes');
      if (maxDailyDeltaMinutes != null) {
        _maxDailyDelta = Duration(minutes: maxDailyDeltaMinutes);
      }
    } catch (e) {
      debugPrint("=====_loadFromPreferences: Error loading preferences: ${e.runtimeType}");
    }
    notifyListeners();
    // docs/TODO.md T-158: populates the direct-boot fallback mirror on every
    // cold start too, not only on the next alarm change - otherwise an
    // install that upgrades from a version predating this mirror would have
    // nothing armed for it until the user happens to touch an alarm.
    refreshDirectBootFallback();
  }
}
