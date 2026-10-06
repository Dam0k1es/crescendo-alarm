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

// docs/TODO.md T-221: a stand-in for the `alarm` plugin's arm/cancel/list
// calls, attached through `AppState`'s `debugPlatform*` seams. The real
// plugin has no channel in `flutter test` (`Alarm.set` throws an
// `AlarmException`, `Alarm.getAlarms` reads an empty store), so without this
// nothing could say whether an alarm is really armed - which is the whole
// question for a switched-off one.

import 'package:alarm/alarm.dart';
import 'package:crescendo_alarm/app_state.dart';

class FakeAlarmPlatform {
  /// What is armed right now, by id.
  final Map<int, AlarmSettings> armed = {};

  /// Every id passed to `Alarm.set`, in order - a re-arm shows up twice.
  final List<int> setIds = [];

  /// Every id passed to `Alarm.stop`, in order.
  final List<int> stopIds = [];

  /// Ids the platform reports as ringing right now (`Alarm.isRinging`).
  final Set<int> ringing = {};

  void attach(AppState appState) {
    appState.debugPlatformSet = (settings) async {
      setIds.add(settings.id);
      armed[settings.id] = settings;
    };
    appState.debugPlatformStop = (id) async {
      stopIds.add(id);
      armed.remove(id);
    };
    appState.debugPlatformGetAll = () async => armed.values.toList();
    appState.debugPlatformIsRinging = (id) async => ringing.contains(id);
  }

  /// Whether anything is armed at [instant]'s whole minute.
  bool armedAt(DateTime instant) {
    final minute = instant.toUtc().millisecondsSinceEpoch ~/ 60000;
    return armed.values.any(
        (a) => a.dateTime.toUtc().millisecondsSinceEpoch ~/ 60000 == minute);
  }

  /// docs/TODO.md T-217 (review N1): what a real Android 15+ force-stop plus
  /// relaunch at [now] does to what `Alarm.getAlarms()` reports. The
  /// force-stop cancels the AlarmManager entries but leaves the plugin's own
  /// storage - which is what `getAlarms` reads - intact; the relaunch's
  /// `Alarm.init` (`_checkAlarm`) then re-arms every future entry and stops
  /// every past one that is not ringing. So: past entries disappear, future
  /// ones stay. Not recorded in [setIds]/[stopIds] - the app did nothing.
  void forceStopAndRelaunch(DateTime now) {
    armed.removeWhere(
        (id, a) => !ringing.contains(id) && !a.dateTime.isAfter(now));
  }
}
