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

// The two permitted readings of a stored plan value (docs/TODO.md T-83),
// plus one stored planned clock time, which is not an instant and meets one
// only through `resolvePlannedClockTime` (docs/TODO.md T-206).
//
// `AppState.pendingDayValues` is a `Map<String, int?>` from ISO date to
// `millisecondsSinceEpoch` - this shape is deliberate, because FR-16's
// checkpoint 2 must read and write the same SharedPreferences key from a
// background isolate with no AppState access at all.
//
// On reading it back there are two *different*, both correct answers, and
// that was exactly the trap: the map used to be read in five places, three
// times with `isUtc: true` and twice without. That was not a bug, but
// necessary - yet it looked like an inconsistency, and a well-meant
// unification would have silently shifted the display and alarm titles by
// the device offset. Hence no more raw `DateTime.fromMillisecondsSinceEpoch`
// calls at the call sites, but two names that carry the intent.

import 'dart:convert';

/// For the **domain layer** (`scheduling_v2.dart`, `replan.dart`):
/// UTC-tagged.
///
/// Its arithmetic used to compare digit fields of instants directly, so all
/// operands had to lie in the same frame - and by convention that is UTC
/// (FR-1: every value is an absolute instant). A locally-tagged value here
/// gave different results depending on the test machine's or the device's
/// time zone; that was exactly T-61. Since docs/TODO.md T-206 the digits it
/// compares are local READINGS made from an instant with the zone's rules
/// (`toUtc()` first), but the convention stays: the domain layer's instants
/// are UTC-tagged.
DateTime? instantFromStored(int? millis) => millis == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

/// For **platform and display** (`apply_alarms.dart`, `next_wake_up.dart`):
/// locally tagged.
///
/// Behind this are readers that interpret the digits as wall-clock time -
/// `ScheduledAlarm.title` via `formatDateTime`, the alarm list in the UI, and
/// `alarmPlatformTime` at the handoff to the alarm plugin. The same real
/// moment as [instantFromStored], just in the reading this side needs.
DateTime? localFromStored(int? millis) =>
    millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

/// The reverse direction. Frame-independent (`millisecondsSinceEpoch` is
/// anyway) and named only for completeness, so the write sites use the same
/// vocabulary as the read sites.
int? toStored(DateTime? value) => value?.millisecondsSinceEpoch;

/// docs/TODO.md T-206 (T206-R11): a stored PLANNED CLOCK TIME
/// (`AppState.pendingDayClockTimes`) - "wall milliseconds", the reading's
/// digits read as UTC. UTC-tagged, and **not an instant**: it is planning
/// intent, never compared with an instant, and meets one only through
/// `resolvePlannedClockTime` (`lib/utils/wall_clock.dart`).
DateTime? clockTimeFromStored(int? wallMillis) => wallMillis == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(wallMillis, isUtc: true);

/// docs/TODO.md T-206 (T206-R11): the reverse of [clockTimeFromStored]. The
/// argument must be a reading (UTC-tagged digits); a local-tagged value here
/// would store the digits shifted by the device offset.
int? clockTimeToStored(DateTime? clockTime) {
  assert(clockTime == null || clockTime.isUtc,
      'a planned clock time is a UTC-tagged reading');
  return clockTime?.millisecondsSinceEpoch;
}

/// docs/TODO.md T-206 (T206-R11): `AppState.pendingDayClockTimes`' stored
/// form, `{"<iso>": {"c": <wall ms>, "v": <instant ms>}}` - shared by
/// `AppState` and FR-16's Checkpoint 2, which reads and writes the same key
/// with no `AppState` at all, so the two cannot disagree on the shape.
String encodePendingDayClockTimes(
        Map<String, ({int clockTime, int value})> entries) =>
    jsonEncode({
      for (final e in entries.entries)
        e.key: {'c': e.value.clockTime, 'v': e.value.value},
    });

/// The reverse of [encodePendingDayClockTimes]. Throws (a `FormatException`
/// or a cast error) when [json] is not an object at all; a single malformed
/// entry is left out instead - for every reader that is the same as "no
/// entry for that day", which falls back to the value (FR-3, FR-16).
Map<String, ({int clockTime, int value})> decodePendingDayClockTimes(
    String json) {
  final decoded = jsonDecode(json) as Map<String, dynamic>;
  return {
    for (final e in decoded.entries)
      if (e.value case {'c': final int c, 'v': final int v})
        e.key: (clockTime: c, value: v),
  };
}
