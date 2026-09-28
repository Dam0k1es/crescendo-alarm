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

// docs/TODO.md T-202: the daylight-saving transitions of the PROCESS's own
// time zone, found at runtime.
//
// Dart's local `DateTime` follows the process zone (`TZ`), so a test about
// how a local wall-clock time resolves can only be meaningful in a zone that
// actually has a transition - and CI runs the suite under six different
// zones (two of them without DST). Hard-coding "Europe/Berlin, 25 Oct 02:30"
// would test nothing under `TZ=Australia/Lord_Howe` and fail spuriously if
// read as local anywhere else. Instead the transitions are derived here
// from the same source the app uses, with a deliberately different
// algorithm (an hourly scan plus bisection over instants) than the
// production resolver's (probing the candidate offsets of one wall-clock
// reading), so the expectations are not the implementation restated.
//
// Not a test file itself (no `_test.dart` suffix): `flutter test` does not
// run it, the test files import it.

/// The local UTC offset at [epochMs], in milliseconds.
int localOffsetMs(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs).timeZoneOffset.inMilliseconds;

const int _minuteMs = 60 * 1000;
const int _hourMs = 60 * _minuteMs;

/// One offset change of the process zone.
class LocalTransition {
  LocalTransition(this.instantMs, this.offsetBeforeMs, this.offsetAfterMs);

  /// The first millisecond at which [offsetAfterMs] applies.
  final int instantMs;
  final int offsetBeforeMs;
  final int offsetAfterMs;

  /// Clocks go back: a range of wall-clock readings occurs twice.
  bool get isOverlap => offsetAfterMs < offsetBeforeMs;

  /// Clocks go forward: a range of wall-clock readings does not exist.
  bool get isGap => offsetAfterMs > offsetBeforeMs;

  int get _lengthMs => (offsetBeforeMs - offsetAfterMs).abs();

  /// The affected range of wall-clock readings, as "wall milliseconds"
  /// (the reading's digits interpreted as UTC): `[start, end)`.
  ///
  /// Overlap: `[T + after, T + before)` - every reading in it occurs once
  /// before [instantMs] (at `wall - before`) and once after (`wall - after`).
  /// Gap: `[T + before, T + after)` - none of these readings exists.
  int get wallStartMs =>
      instantMs + (isOverlap ? offsetAfterMs : offsetBeforeMs);
  int get wallEndMs => wallStartMs + _lengthMs;

  /// A whole-minute wall-clock reading in the middle of the affected range.
  int get wallMiddleMs {
    final middle = wallStartMs + _lengthMs ~/ 2;
    return middle - middle % _minuteMs;
  }

  /// The earlier and the later instant a reading in an overlap refers to.
  int firstPassMs(int wallMs) => wallMs - offsetBeforeMs;
  int secondPassMs(int wallMs) => wallMs - offsetAfterMs;

  @override
  String toString() {
    final at = DateTime.fromMillisecondsSinceEpoch(instantMs, isUtc: true);
    return '${isOverlap ? 'overlap' : 'gap'} at $at UTC '
        '(${offsetBeforeMs ~/ _minuteMs} -> ${offsetAfterMs ~/ _minuteMs} min)';
  }
}

/// A wall-clock reading's fields, from "wall milliseconds".
({int year, int month, int day, int hour, int minute}) wallFields(int wallMs) {
  final f = DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true);
  return (
    year: f.year,
    month: f.month,
    day: f.day,
    hour: f.hour,
    minute: f.minute,
  );
}

/// Every offset change of the process zone between the start of [fromYear]
/// and the end of [toYear] (UTC), located to the millisecond.
List<LocalTransition> localTransitions({int fromYear = 2026, int toYear = 2027}) {
  final result = <LocalTransition>[];
  final end = DateTime.utc(toYear + 1).millisecondsSinceEpoch;
  var t = DateTime.utc(fromYear).millisecondsSinceEpoch;
  var offset = localOffsetMs(t);
  while (t < end) {
    final next = t + _hourMs;
    final nextOffset = localOffsetMs(next);
    if (nextOffset != offset) {
      var lo = t; // still the old offset
      var hi = next; // already the new one
      while (hi - lo > 1) {
        final mid = lo + (hi - lo) ~/ 2;
        if (localOffsetMs(mid) == offset) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      result.add(LocalTransition(hi, offset, nextOffset));
    }
    t = next;
    offset = nextOffset;
  }
  return result;
}

/// Why a DST-specific test has nothing to check under the current `TZ`.
const String noTransitionReason =
    'the process time zone has no DST transition in 2026/2027 - nothing '
    'to resolve here (the other CI time zone legs cover it)';
