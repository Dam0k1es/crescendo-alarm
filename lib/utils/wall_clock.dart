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
// (TZ-3). Since docs/TODO.md T-206 the rules are a PARAMETER of the
// resolver ([ZoneOffsetAt]) rather than read inside it, so the scheduling
// engine can resolve each planned day with the rules for that day and tests
// can inject any zone's rules; in production they are always
// [deviceOffsetAt] - Dart's local `DateTime`, i.e. the operating system's
// own time zone database for the process zone.

/// T206-R1: the device zone's rules as one input - the UTC offset in effect
/// at [instant]. Pure-layer functions receive this as a value, never read it
/// from ambient state, so a test can inject any zone's rules (or one
/// constant offset, [fixedOffset]) and run identically under every process
/// zone (docs/TODO.md T-206).
typedef ZoneOffsetAt = Duration Function(DateTime instant);

/// T206-R1: the production rules - the process zone's offset at [instant],
/// from Dart's local `DateTime` (the OS time zone database, TZ-3). Exact for
/// future instants of the CURRENT zone too; it guesses nothing from a name.
Duration deviceOffsetAt(DateTime instant) =>
    DateTime.fromMicrosecondsSinceEpoch(instant.microsecondsSinceEpoch)
        .timeZoneOffset;

/// T206-R1: rules with one constant [offset] (tests; zones without DST).
ZoneOffsetAt fixedOffset(Duration offset) => (_) => offset;

const int _hourMicros = 60 * 60 * 1000000;
const int _minuteMicros = 60 * 1000000;

/// TZ-1's resolution R of the local clock reading [wallReading] under the
/// zone rules [offsetAt], as a UTC-tagged instant: the later occurrence of a
/// repeated reading, the transition instant for a skipped one, and
/// `reading - offset` for every other reading. The ONE implementation of R
/// (docs/TODO.md T-206, T206-R2); [localWallClockInstant] is a wrapper over
/// the device's rules, and the scheduling engine reaches it through
/// [resolvePlannedClockTime].
///
/// [wallReading] is a READING, not an instant: its digits (a calendar date
/// and a time of day) carried in a UTC-tagged `DateTime` ("wall
/// microseconds"). A local-tagged argument is a programming error - its
/// digits would already have been resolved once, by Dart's own rule. The
/// result keeps the reading's microseconds, except for a skipped reading,
/// which resolves to the transition itself.
///
/// How: the reading's digits are taken as "wall microseconds" `W`. An
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
/// current rules (asserted for every zone by test/t206_dst_sweep_test.dart).
DateTime resolveWallClock(DateTime wallReading, ZoneOffsetAt offsetAt) {
  assert(wallReading.isUtc,
      'resolveWallClock takes a reading (UTC-tagged digits), not a local time');
  final wall = wallReading.microsecondsSinceEpoch;
  int offsetAtMicros(int us) =>
      offsetAt(DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true))
          .inMicroseconds;
  DateTime instant(int us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);

  final offsets = <int>{
    offsetAtMicros(wall - 30 * _hourMicros),
    offsetAtMicros(wall + 30 * _hourMicros),
  };
  if (offsets.length == 1) {
    // No transition anywhere near: the reading is unambiguous.
    return instant(wall - offsets.single);
  }

  final valid = [
    for (final o in offsets)
      if (offsetAtMicros(wall - o) == o) wall - o,
  ];
  if (valid.isNotEmpty) {
    // One candidate: an ordinary reading on a change day. Two: the repeated
    // hour - the later occurrence is the larger instant.
    return instant(valid.reduce((a, b) => a > b ? a : b));
  }

  // A skipped reading. With `before` < `after` (clocks go forward), the
  // candidate `W - after` still lies before the transition and `W - before`
  // already after it; the transition is the first microsecond carrying the
  // new offset.
  var lo = wall - offsets.reduce((a, b) => a > b ? a : b);
  var hi = wall - offsets.reduce((a, b) => a < b ? a : b);
  final newOffset = offsetAtMicros(hi);
  while (hi - lo > 1) {
    final mid = lo + (hi - lo) ~/ 2;
    if (offsetAtMicros(mid) == newOffset) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return instant(hi);
}

/// T206-R3, TZ-2a: R_plan - how the scheduling engine (and a manual alarm,
/// `nextManualOccurrence`) turns a planned clock time [clockTime] (a
/// reading, UTC-tagged as for [resolveWallClock]) into an instant.
///
/// It is [resolveWallClock], except where R would move the value onto a
/// LATER calendar date than the reading's own - a skipped hour that ends at
/// midnight (America/Nuuk, 28 Mar 2026: 23:00 -> 00:00). There it is one
/// minute earlier: the last valid minute before the gap, on the planned day
/// (maintainer decision B, "zur not vorziehen" - pull it earlier if
/// necessary). Since R of a skipped reading
/// is the transition instant, that is the minute right before the
/// transition. The zone's own rules decide when this applies; no zone is
/// named here.
///
/// The one place a planned clock time meets an instant: every other use of a
/// planned clock time is reading arithmetic, and it is never compared with an
/// instant directly.
DateTime resolvePlannedClockTime(DateTime clockTime, ZoneOffsetAt offsetAt) {
  final r = resolveWallClock(clockTime, offsetAt);
  final shown = r.add(offsetAt(r));
  final laterDate = DateTime.utc(shown.year, shown.month, shown.day)
      .isAfter(DateTime.utc(clockTime.year, clockTime.month, clockTime.day));
  return laterDate ? r.subtract(const Duration(microseconds: _minuteMicros)) : r;
}

/// The instant the local wall-clock reading [year]-[month]-[day]
/// [hour]:[minute] refers to, as a local-tagged `DateTime`, resolved by
/// TZ-1's rule (see this file's header): the later occurrence of a repeated
/// reading, the transition instant for a skipped one, and exactly
/// `DateTime(year, month, day, hour, minute)` for every other reading.
/// Field overflow (`day: 32`) normalises like `DateTime`'s constructor.
///
/// A thin wrapper since docs/TODO.md T-206: [resolveWallClock] under the
/// device's rules ([deviceOffsetAt]), returned local-tagged as before.
DateTime localWallClockInstant(
        int year, int month, int day, int hour, int minute) =>
    resolveWallClock(
            DateTime.utc(year, month, day, hour, minute), deviceOffsetAt)
        .toLocal();
