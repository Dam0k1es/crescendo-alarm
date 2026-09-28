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

// docs/TODO.md T-202, TZ-1/TZ-3: `localWallClockInstant` is the ONE place a
// local wall-clock reading becomes an instant under the app's own rule
// (repeated -> later occurrence, skipped -> the transition instant), using
// the device's own zone rules. This checks it exhaustively against the
// process zone's transitions in 2026/2027: every minute of each affected
// range and an hour on either side, plus every ordinary day.

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/local_zone_transitions.dart';

const _minute = 60 * 1000;
const _hour = 60 * _minute;

int _resolve(int wallMs) {
  final f = wallFields(wallMs);
  return localWallClockInstant(f.year, f.month, f.day, f.hour, f.minute)
      .millisecondsSinceEpoch;
}

void main() {
  final transitions = localTransitions();

  test('every minute in and around each transition follows TZ-1', () {
    for (final t in transitions) {
      for (var wall = t.wallStartMs - _hour;
          wall < t.wallEndMs + _hour;
          wall += _minute) {
        final int expected;
        if (wall < t.wallStartMs) {
          expected = wall - t.offsetBeforeMs; // unique, old offset
        } else if (wall >= t.wallEndMs) {
          expected = wall - t.offsetAfterMs; // unique, new offset
        } else if (t.isOverlap) {
          expected = t.secondPassMs(wall); // the later occurrence
        } else {
          expected = t.instantMs; // the first valid instant after the gap
        }
        expect(_resolve(wall), expected,
            reason: '$t, reading ${wallFields(wall)}');
      }
    }
  }, skip: transitions.isEmpty ? noTransitionReason : false);

  test('the result is local-tagged and, in a gap, reads as the first valid '
      'time after it', () {
    for (final t in transitions.where((t) => t.isGap)) {
      final f = wallFields(t.wallMiddleMs);
      final r = localWallClockInstant(f.year, f.month, f.day, f.hour, f.minute);
      final after = wallFields(t.wallEndMs);
      expect(r.isUtc, isFalse);
      expect((r.day, r.hour, r.minute), (after.day, after.hour, after.minute),
          reason: '$t');
    }
  }, skip: transitions.where((t) => t.isGap).isEmpty ? noTransitionReason : false);

  test('counter-test: on every other reading it is exactly DateTime(...)', () {
    bool affected(int wallMs) => transitions
        .any((t) => wallMs >= t.wallStartMs && wallMs < t.wallEndMs);
    for (var day = DateTime.utc(2026, 1, 1);
        day.isBefore(DateTime.utc(2028, 1, 1));
        day = DateTime.utc(day.year, day.month, day.day + 1)) {
      for (final (h, m) in const [(0, 0), (1, 30), (2, 30), (3, 0), (7, 0), (23, 59)]) {
        final wall = DateTime.utc(day.year, day.month, day.day, h, m)
            .millisecondsSinceEpoch;
        if (affected(wall)) continue;
        expect(localWallClockInstant(day.year, day.month, day.day, h, m),
            DateTime(day.year, day.month, day.day, h, m),
            reason: 'reading ${wallFields(wall)}');
      }
    }
  });

  test('field overflow is normalised like DateTime\'s own constructor', () {
    expect(localWallClockInstant(2026, 7, 32, 7, 0), DateTime(2026, 8, 1, 7, 0));
    expect(localWallClockInstant(2026, 12, 31, 24, 0), DateTime(2027, 1, 1, 0, 0));
  });
}
