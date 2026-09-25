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

/// Which alarms a successful deactivation scan is allowed to stop.
///
/// Pure, and in its own file, because an independent review found the decision
/// wrong in a way no camera-driven test could have shown: the import screen
/// builds the scanner without an `alarmId`, and the old rule "no id given, so
/// stop everything" then cancelled every armed alarm while nothing was ringing
/// at all. Scheduled alarms recover at the next checkpoint - `planAlarmSync`
/// re-creates a planned day whose platform alarm is missing - but **manual
/// alarms do not**: nothing re-arms those. They stay in the list, switched on,
/// and never ring again. A silent oversleep is the worst outcome this app has.
///
/// [ringingAlarmId] is what `Handler.handleAlarm` knows and passes on;
/// [anythingRinging] is the platform's answer to "is anything ringing at all".
List<int> deactivationStopTargets({
  required int? ringingAlarmId,
  required List<int> platformAlarmIds,
  required bool anythingRinging,
}) {
  // docs/TODO.md T-74e: stop exactly the alarm that rang when we know which one
  // it is. Stopping the others cancelled them at the platform while AppState
  // still believed they existed - a divergence FR-18's sync could not see.
  if (ringingAlarmId != null) return <int>[ringingAlarmId];

  // Nothing is ringing, so there is nothing a scan needs to silence.
  if (!anythingRinging) return const <int>[];

  // Something rings and nobody said which. The fallback stays, because the
  // alternative is worse: an alarm ringing on despite the correct code.
  return platformAlarmIds;
}
