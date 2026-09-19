// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

// The two permitted readings of a stored plan value
// (docs/TODO.md T-83).
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

/// For the **domain layer** (`scheduling_v2.dart`, `replan.dart`):
/// UTC-tagged.
///
/// Its arithmetic compares digit fields (`_wallClockDelta` reads
/// `.hour`/`.minute`), so all operands must lie in the same frame - and by
/// convention that is UTC (FR-1: every value is an absolute instant). A
/// locally-tagged value here would give different results depending on the
/// test machine's or the device's time zone; that was exactly T-61.
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
