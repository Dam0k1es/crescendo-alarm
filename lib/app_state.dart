import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/utils.dart';

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
  int _startOfWeekDay = 1;
  List<DateTime> _fetchedCalendarWeeks = [];
  List<Meeting> _meetings = [];
  DateTime _visibleDate =
      DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  // Scan Code Screen variables
  DeactivationCode? _deactivationCode;

  // Sleep Goal Configuration variables
  TimeOfDay _sleepGoal = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _durationToWakeUp = const TimeOfDay(hour: 0, minute: 30);
  TimeOfDay _wakeUpSteps = const TimeOfDay(hour: 1, minute: 0);
  TimeOfDay _durationToGetReady = const TimeOfDay(hour: 1, minute: 0);

  bool _reminderEnabled = false;
  TimeOfDay _reminderDuration = const TimeOfDay(hour: 0, minute: 30);
  bool _gentleWakeUpEnabled = false;
  bool _doNotDisturbEnabled = false;
  bool _turnOffNotifications = false;
  bool _turnOffCalls = false;
  bool _rescheduleOnAlarm = true;

  // Theming variables
  bool _darkMode = false;
  Color _accentColor = Colors.blue;

  // Alarm tone and volume variables
  String _selectedTone = 'assets/sounds/lollipop.mp3';
  double _selectedVolume = 0.8;

  // State variables
  bool _permissionsGranted = false;
  bool _isReadingCalendarMutex = false;
  bool _isPreloadingCalendarMutex = false;
  bool _firstUpdateOfCalendar = true;

  AppState() {
    initialized = _loadFromPreferences();
  }

  // Getter
  int get currentPageIndex => _currentPageIndex;

  DeactivationCode? get deactivationCode => _deactivationCode;

  bool get reminderEnabled => _reminderEnabled;

  bool get gentleWakeUpEnabled => _gentleWakeUpEnabled;

  bool get doNotDisturbEnabled => _doNotDisturbEnabled;

  bool get turnOffNotifications => _turnOffNotifications;

  bool get turnOffCalls => _turnOffCalls;

  bool get rescheduleOnAlarm => _rescheduleOnAlarm;

  bool get calendarsInitialized => _calendarsInitialized;

  bool get firstUpdateOfCalendar => _firstUpdateOfCalendar;

  int get startOfWeekDay => _startOfWeekDay;

  bool get darkMode => _darkMode;

  TimeOfDay get sleepGoal => _sleepGoal;

  TimeOfDay get durationToWakeUp => _durationToWakeUp;

  TimeOfDay get wakeUpSteps => _wakeUpSteps;

  // TODO durationToGetReady per Weekday - 0x399
  TimeOfDay get durationToGetReady => _durationToGetReady;

  TimeOfDay get reminderDuration => _reminderDuration;

  DateTime get visibleDate => _visibleDate;

  List<Meeting> get meetings => _meetings;

  List<DateTime> get fetchedCalendarWeeks => _fetchedCalendarWeeks;

  List<ManualAlarm> get manualAlarms => _manualAlarms;

  List<ScheduledAlarm> get scheduledAlarms => _scheduledAlarms;

  Color get accentColor => _accentColor;

  bool get isReadingCalendarMutex => _isReadingCalendarMutex;

  String get currentTimeZone => _currentTimeZone;

  bool get isPreloadingCalendarMutex => _isPreloadingCalendarMutex;

  bool get permissionsGranted => _permissionsGranted;

  String get selectedTone => _selectedTone;

  double get selectedVolume => _selectedVolume;

  // Setter
  set currentPageIndex(int index) {
    _currentPageIndex = index;
    _prefs.setInt('currentPageIndex', _currentPageIndex);
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

  set doNotDisturbEnabled(bool value) {
    _doNotDisturbEnabled = value;
    _prefs.setBool('doNotDisturbEnabled', _doNotDisturbEnabled);
    notifyListeners();
  }

  set turnOffNotifications(bool value) {
    _turnOffNotifications = value;
    _prefs.setBool('turnOffNotifications', _turnOffNotifications);
    notifyListeners();
  }

  set turnOffCalls(bool value) {
    _turnOffCalls = value;
    _prefs.setBool('turnOffCalls', _turnOffCalls);
    notifyListeners();
  }

  set rescheduleOnAlarm(bool value) {
    _rescheduleOnAlarm = value;
    _prefs.setBool('rescheduleOnAlarm', _rescheduleOnAlarm);
    notifyListeners();
  }

  set sleepGoal(TimeOfDay value) {
    _sleepGoal = value;
    _prefs.setString('sleepGoal', '${_sleepGoal.hour}:${_sleepGoal.minute}');
    notifyListeners();
  }

  set durationToWakeUp(TimeOfDay value) {
    _durationToWakeUp = value;
    _prefs.setString('durationToWakeUp',
        '${_durationToWakeUp.hour}:${_durationToWakeUp.minute}');
    notifyListeners();
  }

  set wakeUpSteps(TimeOfDay value) {
    _wakeUpSteps = value;
    _prefs.setString(
        'wakeUpSteps', '${_wakeUpSteps.hour}:${_wakeUpSteps.minute}');
    notifyListeners();
  }

  set durationToGetReady(TimeOfDay value) {
    _durationToGetReady = value;
    _prefs.setString('durationToGetReady',
        '${_durationToGetReady.hour}:${_durationToGetReady.minute}');
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

  set visibleDate(DateTime value) {
    _visibleDate = value;
    // Must not persist
    // String dateTimeString = _visibleDate.toIso8601String();
    // final visibleDataJSON = jsonEncode({'date': dateTimeString});
    // _prefs.setString('visibleDate', visibleDataJSON);
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

  set startOfWeekDay(int value) {
    _startOfWeekDay = value;
    _prefs.setInt('startOfWeekDay', _startOfWeekDay);
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

  set isPreloadingCalendarMutex(bool value) {
    _isPreloadingCalendarMutex = value;
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
          tone: alarm.tone,
          volume: alarm.volume,
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
      await _setAlarm(newAlarm, alarmDateTime);
    } else if (alarm is ScheduledAlarm) {
      // Create a new alarm in case it was set to a DayTime in the past
      ScheduledAlarm newAlarm = ScheduledAlarm(
          id: alarm.id,
          time: alarm.time,
          title: alarm.title,
          enabled: alarm.enabled,
          gentlewake: alarm.gentlewake,
          tone: alarm.tone);
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
        await _setAlarm(newAlarm, alarmDateTime);
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
      debugPrint("=====getAlarm: $e");
    }
    try {
      for (MyAlarm alarm in _scheduledAlarms) {
        if (alarm.id == id) {
          return alarm;
        }
      }
    } catch (e) {
      debugPrint("=====getAlarm: $e");
    }
    return null;
  }

  DateTime _getAlarmTime(MyAlarm alarm) {
    DateTime now = DateTime.now();
    DateTime alarmDateTime = now;

    if (alarm is ManualAlarm) {
      debugPrint(
          "=====getAlarmTime: ${alarm.id} is a manual alarm set on ${alarm.time}");
      // Initalize with alarm.time as TimeOfDay
      alarmDateTime = DateTime(
          now.year, now.month, now.day, alarm.time.hour, alarm.time.minute);
      // Only alarms in the future are allowed to be set
      if (alarmDateTime.isBefore(now)) {
        alarmDateTime = alarmDateTime.add(const Duration(days: 1));
      }
    }

    if (alarm is ScheduledAlarm) {
      debugPrint(
          "=====getAlarmTime: ${alarm.id} is a scheduled alarm set on ${alarm.time}");
      // Initalize with alarm.time as DateTime
      alarmDateTime = DateTime(alarm.time.year, alarm.time.month,
          alarm.time.day, alarm.time.hour, alarm.time.minute);
    }

    return alarmDateTime;
  }

  Future<void> _setAlarm(MyAlarm alarm, DateTime alarmDateTime) async {
    // Set the alarm with the proper settings
    final alarmSettings = AlarmSettings(
      id: alarm.id,
      dateTime: DateTime(
        alarmDateTime.year,
        alarmDateTime.month,
        alarmDateTime.day,
        alarmDateTime.hour,
        alarmDateTime.minute,
      ),
      assetAudioPath: alarm.tone,
      volumeSettings: alarm.gentlewake
          ? VolumeSettings.fade(
              volume: alarm.volume,
              fadeDuration: const Duration(seconds: 60),
            )
          : VolumeSettings.fixed(volume: alarm.volume),
      notificationSettings: NotificationSettings(
        title: alarm.title,
        body: "Your alarm is ringing",
      ),
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
    );

    // Set the alarm
    await Alarm.set(alarmSettings: alarmSettings);
  }

  Future<void> _stopAlarm(int id) async {
    await Alarm.stop(id);
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
          "=====_loadScheduledAlarms: Error loading scheduled alarms: $e");
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
      debugPrint("=====_loadManualAlarms: Error loading manual alarms: $e");
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
          "=====_loadDeactivationCode: Error loading deactivation code: $e");
      return null;
    }
  }

  TimeOfDay? _loadSleepGoal() {
    try {
      final data = _prefs.getString('sleepGoal');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint("=====_loadSleepGoal: Error loading sleep goal: $e");
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
          "=====_loadDurationToWakeUp: Error loading durationToWakeUp: $e");
      return null;
    }
  }

  TimeOfDay? _loadWakeUpSteps() {
    try {
      final data = _prefs.getString('wakeUpSteps');
      if (data == null) return null;
      return timeOfDayFromString(data);
    } catch (e) {
      debugPrint("=====_loadWakeUpSteps: Error loading wakeUpSteps: $e");
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
          "=====_loadDurationToGetReady: Error loading durationToGetReady: $e");
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
          "=====_loadReminderDuration: Error loading reminderDuration: $e");
      return null;
    }
  }

  // DateTime _loadVisibleDate() {
  //   final visibleDate = _prefs.getString('visibleDate');
  //   if (visibleDate == null) {
  //     return DateTime.now();
  //   } else {
  //     final date = DateTime.parse(jsonDecode(visibleDate)['date']);
  //     return date;
  //   }
  // }

  Future<bool> isCalendarWeekFetched(DateTime dateTime) async {
    DateTime dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);

    try {
      for (DateTime fetchedDate in _fetchedCalendarWeeks) {
        if (fetchedDate.year == dateOnly.year &&
            fetchedDate.month == dateOnly.month &&
            fetchedDate.day == dateOnly.day) {
          debugPrint(
              "=====isCalendarWeekFetched: $visibleDate has been fetched. (See $fetchedCalendarWeeks)");
          return true;
        }
      }
    } catch (e) {
      debugPrint("=====isCalendarWeekFetched: $e");
      return false;
    }

    debugPrint(
        "=====updateCalendarData: ${appState.visibleDate} has not been fetched. (See ${appState.fetchedCalendarWeeks})");
    return false;
  }

  // only overrides values not being already set
  Future<void> _loadFromPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    // A failure below must never leave _prefs unassigned or throw out of
    // this method: main() awaits `initialized` before runApp(), so any
    // unhandled error here would prevent the app from starting at all.
    // Corrupted or incompatible persisted data should fall back to defaults
    // instead of crashing the app on launch.
    try {
      // _currentPageIndex = _prefs.getInt('currentPageIndex') ?? _currentPageIndex;
      _permissionsGranted =
          _prefs.getBool('permissionsGranted') ?? _permissionsGranted;
      _reminderEnabled = _prefs.getBool('reminderEnabled') ?? _reminderEnabled;
      _gentleWakeUpEnabled =
          _prefs.getBool('gentleWakeUpEnabled') ?? _gentleWakeUpEnabled;
      _doNotDisturbEnabled =
          _prefs.getBool('doNotDisturbEnabled') ?? _doNotDisturbEnabled;
      _turnOffNotifications =
          _prefs.getBool('turnOffNotifications') ?? _turnOffNotifications;
      _turnOffCalls = _prefs.getBool('turnOffCalls') ?? _turnOffCalls;
      _sleepGoal = _loadSleepGoal() ?? _sleepGoal;
      _durationToWakeUp = _loadDurationToWakeUp() ?? _durationToWakeUp;
      _wakeUpSteps = _loadWakeUpSteps() ?? _wakeUpSteps;
      _durationToGetReady = _loadDurationToGetReady() ?? _durationToGetReady;
      _reminderDuration = _loadReminderDuration() ?? _reminderDuration;
      _scheduledAlarms = _loadScheduledAlarms() ?? _scheduledAlarms;
      _manualAlarms = _loadManualAlarms() ?? _manualAlarms;
      _selectedTone = _prefs.getString('selectedTone') ?? _selectedTone;
      _selectedVolume = _prefs.getDouble('selectedVolume') ?? _selectedVolume;
      _darkMode = _prefs.getBool('darkMode') ?? _darkMode;
      _accentColor =
          Color(_prefs.getInt('accentColor') ?? _accentColor.toARGB32());
      _deactivationCode = _loadDeactivationCode();
      // Set Monday as the first day of the week by default:
      _startOfWeekDay = _prefs.getInt('startOfWeekDay') ?? _startOfWeekDay;
    } catch (e) {
      debugPrint("=====_loadFromPreferences: Error loading preferences: $e");
    }
    notifyListeners();
  }
}
