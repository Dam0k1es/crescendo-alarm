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

// docs/TODO.md T-202, docs/timezone-requirements.md TZ-1/TZ-3: turning a
// local wall-clock reading ("day D, 02:30") into an instant, in ONE place.
//
// On a daylight-saving change day a reading can name two instants (clocks
// go back: 02:30 occurs twice) or none (clocks go forward: 02:30 does not
// exist). The maintainer's decisions for a wall-clock alarm:
//
// - repeated reading -> the LATER occurrence (it rings once, then);
// - skipped reading  -> the first valid instant after the gap, i.e. the
//   transition itself (03:00 in Europe/Berlin). Never skipped.
//
// No platform default matches both: Dart's `DateTime(y, m, d, h, min)`
// picks the FIRST occurrence and shifts a skipped reading by the gap length
// (02:30 -> 03:30); `package:timezone` picks the later occurrence only in
// some zones and would substitute its own bundled database for the
// device's; `java.time`'s default is also earlier/shifted
// (docs/timezone-travel-analysis.md, section 3.1).
//
// So only the RESOLUTION is the app's own; the zone RULES stay the device's
// (TZ-3): every offset below comes from Dart's local `DateTime`, i.e. the
// operating system's own time zone database for the process zone.

const int _hourMs = 60 * 60 * 1000;

/// The local UTC offset in effect at [epochMs], in milliseconds.
int _offsetAt(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs).timeZoneOffset.inMilliseconds;

/// The instant the local wall-clock reading [year]-[month]-[day]
/// [hour]:[minute] refers to, as a local-tagged `DateTime`, resolved by
/// TZ-1's rule (see this file's header): the later occurrence of a repeated
/// reading, the transition instant for a skipped one, and exactly
/// `DateTime(year, month, day, hour, minute)` for every other reading.
/// Field overflow (`day: 32`) normalises like `DateTime`'s constructor.
///
/// How: the reading's digits are taken as "wall milliseconds" `W`. An
/// instant `t` shows that reading exactly when `t = W - offset(t)`, so each
/// offset the zone uses around `W` is one candidate `W - o`, valid if the
/// zone really uses `o` at that instant. Two valid candidates are the two
/// passes of a repeated reading (the larger one is the later occurrence);
/// none means the reading falls into a gap, whose transition instant then
/// lies between the two invalid candidates and is found by bisection.
///
/// The probes 30 hours either side of `W` see the offsets before and after
/// any transition near the reading (every real offset lies within ±14 h,
/// so no candidate instant is further than 14 h from `W`); zones changing
/// their offset twice within that span do not exist in the tz database's
/// current rules.
DateTime localWallClockInstant(
    int year, int month, int day, int hour, int minute) {
  final wall = DateTime.utc(year, month, day, hour, minute).millisecondsSinceEpoch;

  final offsets = <int>{
    _offsetAt(wall - 30 * _hourMs),
    _offsetAt(wall + 30 * _hourMs),
  };
  if (offsets.length == 1) {
    // No transition anywhere near: the reading is unambiguous.
    return DateTime.fromMillisecondsSinceEpoch(wall - offsets.single);
  }

  final valid = [
    for (final o in offsets)
      if (_offsetAt(wall - o) == o) wall - o,
  ];
  if (valid.isNotEmpty) {
    // One candidate: an ordinary reading on a change day. Two: the repeated
    // hour - the later occurrence is the larger instant.
    return DateTime.fromMillisecondsSinceEpoch(
        valid.reduce((a, b) => a > b ? a : b));
  }

  // A skipped reading. With `before` < `after` (clocks go forward), the
  // candidate `W - after` still lies before the transition and `W - before`
  // already after it; the transition is the first millisecond carrying the
  // new offset.
  var lo = wall - offsets.reduce((a, b) => a > b ? a : b);
  var hi = wall - offsets.reduce((a, b) => a < b ? a : b);
  final newOffset = _offsetAt(hi);
  while (hi - lo > 1) {
    final mid = lo + (hi - lo) ~/ 2;
    if (_offsetAt(mid) == newOffset) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(hi);
}
