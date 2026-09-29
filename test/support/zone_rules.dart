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

// Ids used below - tests T01 ..., requirements T206-R1 ..., and "requirements"
// section numbers such as b.0 or 8.2 - are defined in
// docs/t206-dst-requirements.md (not docs/TODO.md items: T33 is not T-33).

// docs/TODO.md T-206: injected zone rules for the pure layer and for
// `replan`/checkpoint tests (requirements b.0).
//
// `package:timezone`'s offset LOOKUP (`Location.timeZone(ms).offset`) is
// exact; only its CONSTRUCTION of a local reading disagrees with TZ-1 in a
// gap or an overlap - and construction is never used for an expectation
// inside an affected range here (only for unique readings, e.g. window-day
// midnights and 07:00). Every expected instant inside a gap or overlap is a
// literal taken from the Python `zoneinfo` computation in the requirements'
// section 8.
//
// Not a test file itself (no `_test.dart` suffix).

import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/utils/wall_clock.dart';

/// The zone rules of [loc] as a [ZoneOffsetAt] (requirements b.0).
///
/// (`package:timezone` 0.11's `TimeZone.offset` is already a `Duration`; the
/// requirements' sketch wrapped it in `Duration(milliseconds: ...)` for the
/// older int-valued API.)
ZoneOffsetAt zoneRules(tz.Location loc) =>
    (DateTime t) => loc.timeZone(t.millisecondsSinceEpoch).offset;

/// A local clock READING (requirements, section 0): its digits carried as a
/// UTC-tagged `DateTime`. Not an instant.
DateTime wall(int year, int month, int day,
        [int hour = 0,
        int minute = 0,
        int second = 0,
        int millisecond = 0,
        int microsecond = 0]) =>
    DateTime.utc(
        year, month, day, hour, minute, second, millisecond, microsecond);

/// L(t): the reading [rules] show at the instant [t], UTC-tagged.
DateTime readingOf(DateTime t, ZoneOffsetAt rules) =>
    t.toUtc().add(rules(t));
