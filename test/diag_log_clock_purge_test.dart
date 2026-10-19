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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';

// docs/TODO.md T-235 (audit G4-01, maintainer decision 2026-10-20): switching
// "Also record wake and appointment times" off left the recorded clock times
// in the log, while the export header then said "no wake times by design".
// Turning the switch off must delete them - from the in-memory ring buffer and
// from both persisted sinks.

bool _carriesClockTimes(DiagRecord r) =>
    r.event == DiagEvent.dayPlanned ||
    r.event == DiagEvent.dayEventTime ||
    (r.event == DiagEvent.planInputs &&
        (r.fields[DiagField.preferredWakeUpMinuteOfDay] ?? -1) != -1);

void _recordWithClockTimes() {
  Diag.setIncludeClockTimes(true);
  Diag.planInputs(
      maxDailyDeltaMinutes: 60,
      wakeUpMinutes: 15,
      getReadyMinutes: 45,
      preferredWakeUpMinuteOfDay: 420);
  Diag.dayPlanned(
      dayOffset: 1, plannedMinuteOfDay: 400, earliestEventMinuteOfDay: 480);
  Diag.dayEventTime(dayOffset: 1, startMinuteOfDay: 480, endMinuteOfDay: 540);
  Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Diag.resetForTest();
    await Diag.init(isolate: LogIsolate.main, enabled: true);
  });

  test('T-235: purging removes every clock value from the ring buffer and '
      'keeps everything else', () async {
    _recordWithClockTimes();
    expect(Diag.records.where(_carriesClockTimes), hasLength(3));

    Diag.setIncludeClockTimes(false);
    await Diag.purgeClockTimes();

    expect(Diag.records.where(_carriesClockTimes), isEmpty);
    expect(Diag.records.map((r) => r.event),
        containsAll(<DiagEvent>[DiagEvent.planInputs, DiagEvent.qrGate]),
        reason: 'the plan inputs stay, with the wake time reset to -1');
  });

  test('T-235: purging also cleans both persisted sinks', () async {
    _recordWithClockTimes();
    await Diag.flush();
    final prefs = await SharedPreferences.getInstance();
    // The same records also persisted under the background isolate's key.
    await prefs.setString(
        Diag.prefsKeyIsolate, prefs.getString(Diag.prefsKeyMain)!);

    Diag.setIncludeClockTimes(false);
    await Diag.purgeClockTimes();

    for (final key in <String>[Diag.prefsKeyMain, Diag.prefsKeyIsolate]) {
      final stored = (jsonDecode(prefs.getString(key)!) as List<dynamic>)
          .map((e) => DiagRecord.decode(e as List<dynamic>)!)
          .toList();
      expect(stored, isNotEmpty, reason: key);
      expect(stored.where(_carriesClockTimes), isEmpty, reason: key);
    }
  });

  test('T-235: the export no longer contains clock values after the purge',
      () async {
    _recordWithClockTimes();
    await Diag.flush();
    expect(Diag.render(await Diag.readAll()), contains('dayPlanned'),
        reason: 'precondition: the clock times reached the persisted log');
    Diag.setIncludeClockTimes(false);
    await Diag.purgeClockTimes();

    final text = Diag.render(await Diag.readAll());
    expect(text, contains('no wake times by design'));
    expect(text, isNot(contains('dayPlanned')));
    expect(text, isNot(contains('dayEventTime')));
    expect(text, isNot(contains('preferredWakeUpMinuteOfDay=420')));
  });
}

