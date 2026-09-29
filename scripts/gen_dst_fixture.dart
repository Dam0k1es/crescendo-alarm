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

// docs/TODO.md T-206 (TZ-9, requirements b.6): the ORACLE table for
// test/t206_dst_sweep_test.dart.
//
// For every zone `package:timezone` knows that changes its UTC offset in
// 2026/2027, this records each transition (instant, offset before/after) and
// R_plan - TZ-1's resolution R with TZ-2a's fallback - for every whole
// 15-minute reading from one hour before to one hour after the affected
// range, plus 07:00 and 00:30 on the change date.
//
// Why package:timezone's data and not the system tzdata: the sweep plans with
// `package:timezone`'s rules (it cannot inject the operating system's rules
// for a zone other than the process's own), so its expected values must come
// from the SAME rules source, or a database difference between the two
// (nine zones as of package:timezone 0.11.1 vs tzdata 2026c) reads as a
// planning defect. The system tzdata table from scripts/gen_dst_fixture.py is
// kept as an informational cross-check next to it.
//
// Independent of the app's ALGORITHM: R is found by a brute-force minute scan
// of TZ-1's definition - of all instants showing the reading `w`, the latest;
// if none does (a skipped reading), the first instant showing a later one -
// not by the app's probing and bisection.
//
// Usage (from the repository root):
//   dart run scripts/gen_dst_fixture.dart > test/fixtures/dst_transitions_2026_2027.json

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _minuteMs = 60 * 1000;
final _start = DateTime.utc(2026);
final _end = DateTime.utc(2028);

Future<void> main() async {
  tzdata.initializeTimeZones();
  final dataVersion = await _dataVersion();
  final zones = <String, List<Map<String, Object>>>{};
  var count = 0;
  final names = tz.timeZoneDatabase.locations.keys.toList()..sort();
  for (final name in names) {
    final loc = tz.timeZoneDatabase.locations[name]!;
    int offsetMin(int minute) => loc.timeZone(minute * _minuteMs).offset.inMinutes;
    int reading(int minute) => minute + offsetMin(minute);

    final rows = <Map<String, Object>>[];
    for (final (t, before, after) in _transitions(offsetMin)) {
      final gap = after > before;
      final start = t + (gap ? before : after);
      final end = t + (gap ? after : before);
      final changeDay = start - start % (24 * 60);
      final readings = <int>{};
      var w = start - 60;
      w -= w % 15;
      for (; w <= end + 60; w += 15) {
        readings.add(w);
      }
      readings
        ..add(changeDay + 7 * 60)
        ..add(changeDay + 30);

      // R by brute force over every minute that could show the reading.
      int resolve(int w) {
        final lo = w - (before > after ? before : after) - 120;
        final hi = w - (before < after ? before : after) + 120;
        int? latest;
        for (var m = lo; m <= hi; m++) {
          if (reading(m) == w) latest = m;
        }
        if (latest != null) return latest;
        var m = hi;
        while (reading(m - 1) >= w) {
          m--;
        }
        return m;
      }

      // R_plan (TZ-2a): R, or one minute earlier when R reads a later date.
      int planned(int w) {
        final r = resolve(w);
        return reading(r) ~/ (24 * 60) > w ~/ (24 * 60) ? r - 1 : r;
      }

      rows.add({
        't': t,
        'before': before,
        'after': after,
        'changeDate': DateTime.fromMillisecondsSinceEpoch(changeDay * _minuteMs,
                isUtc: true)
            .toIso8601String()
            .substring(0, 10),
        'rplan': [
          for (final w in readings.toList()..sort()) [w, planned(w)],
        ],
      });
      count++;
    }
    if (rows.isNotEmpty) zones[name] = rows;
  }

  stdout.writeln(jsonEncode({
    'generator': 'scripts/gen_dst_fixture.dart',
    'source': 'package:timezone ${_packageVersion()} (bundled database, '
        'latest_all)',
    'tzdata': dataVersion,
    'from': _start.toIso8601String(),
    'to': _end.toIso8601String(),
    'units': 'minutes since the Unix epoch; readings as wall minutes (their '
        'digits read as UTC); offsets in minutes',
    'zoneCount': zones.length,
    'transitionCount': count,
    'zones': zones,
  }));
}

/// Every offset change in [_start, _end): an hourly scan, then bisection to
/// the minute.
List<(int, int, int)> _transitions(int Function(int minute) offsetMin) {
  final out = <(int, int, int)>[];
  final end = _end.millisecondsSinceEpoch ~/ _minuteMs;
  var t = _start.millisecondsSinceEpoch ~/ _minuteMs;
  var prev = offsetMin(t);
  while (t < end) {
    final next = t + 60;
    final off = offsetMin(next);
    if (off != prev) {
      var lo = t, hi = next;
      while (hi - lo > 1) {
        final mid = lo + (hi - lo) ~/ 2;
        if (offsetMin(mid) == prev) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      out.add((hi, prev, off));
      prev = off;
    }
    t = next;
  }
  return out;
}

/// The IANA release package:timezone's bundled database was built from, as
/// its generated data file's header states ("Timezone data version: 2025c").
Future<String> _dataVersion() async {
  final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:timezone/data/latest_all.dart'));
  if (uri == null) return 'unknown';
  const marker = '// Timezone data version: ';
  for (final line in File.fromUri(uri).readAsLinesSync().take(10)) {
    if (line.startsWith(marker)) return line.substring(marker.length).trim();
  }
  return 'unknown';
}

/// The resolved `timezone` package version, from pubspec.lock.
String _packageVersion() {
  final lock = File('pubspec.lock').readAsLinesSync();
  for (var i = 0; i < lock.length; i++) {
    if (lock[i] == '  timezone:') {
      for (var j = i + 1; j < lock.length && j < i + 8; j++) {
        final line = lock[j].trim();
        if (line.startsWith('version:')) {
          return line.substring('version:'.length).trim().replaceAll('"', '');
        }
      }
    }
  }
  return 'unknown';
}
