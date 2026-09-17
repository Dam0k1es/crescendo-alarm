import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

// docs/TODO.md T-89: behavior of the PII-free event logger. The
// structural assertion (no String parameters) is checked against the
// source by test/diag_log_api_test.dart; this file is about the semantics.

class _Boom implements Exception {}

Future<void> _freshDiag({
  LogIsolate isolate = LogIsolate.main,
  bool enabled = true,
  bool clearPrefs = true,
}) async {
  if (clearPrefs) SharedPreferences.setMockInitialValues(<String, Object>{});
  Diag.resetForTest();
  await Diag.init(isolate: isolate, enabled: enabled);
}

void main() {
  group('ring buffer', () {
    test('holds at most `capacity` events and discards the oldest',
        () async {
      await _freshDiag();

      for (var i = 0; i < Diag.capacity + 88; i++) {
        Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);
      }

      expect(Diag.records.length, Diag.capacity);
      // The first 88 have rolled out: the smallest remaining sequence
      // number is 88.
      expect(Diag.records.first.seq, 88);
      expect(Diag.records.last.seq, Diag.capacity + 87);
    });

    test('nothing is recorded when disabled', () async {
      await _freshDiag(enabled: false);

      Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);
      Diag.failure(
          at: DiagEvent.qrGate, exceptionType: _Boom, kind: ErrorKind.state);

      expect(Diag.records, isEmpty);
    });

    test('every event carries boot number, sequence, and isolate', () async {
      await _freshDiag();

      Diag.alarmDismissed(route: DismissRoute.qrScan, stopFailed: false);

      final record = Diag.records.single;
      expect(record.boot, Diag.bootSeq);
      expect(record.seq, 0);
      expect(record.fields[DiagField.isolate], LogIsolate.main.code);
      // No timestamp field - only a coarse uptime bucket.
      expect(record.uptime, UptimeBucket.firstMinute);
    });

    test('the boot number counts up across app starts', () async {
      await _freshDiag();
      final first = Diag.bootSeq;
      await _freshDiag(clearPrefs: false);

      expect(Diag.bootSeq, first + 1);
    });
  });

  group('encoding', () {
    test('encode/decode is lossless', () async {
      await _freshDiag();
      Diag.dayAdvance(
        needsDayAdvance: true,
        hadProgressMarker: false,
        daysProcessed: 3,
        daysWithHardFloor: 1,
        gapCounterBefore: 0,
        gapCounterAfter: 2,
        missedAppointmentFlagged: true,
      );

      final encoded = Diag.records.single.encode();
      final decoded = DiagRecord.decode(encoded)!;

      expect(decoded.event, DiagEvent.dayAdvance);
      expect(decoded.seq, 0);
      expect(decoded.fields[DiagField.daysProcessed], 3);
      expect(decoded.fields[DiagField.gapCounterAfter], 2);
      expect(decoded.fields[DiagField.missedAppointmentFlagged], 1);
    });

    test('encode produces only numbers', () async {
      await _freshDiag();
      Diag.calendarRead(
        outcome: CalendarOutcome.ok,
        calendarCount: 2,
        eventCount: 5,
        allDayEventCount: 1,
        lazyInitTriggered: false,
        took: DurationBucket.under200,
      );

      expect(Diag.records.single.encode(), everyElement(isA<int>()));
    });

    test('an unknown event code is discarded on decode', () {
      // Forward compatibility: a log from a newer app version must not
      // crash an older one.
      expect(DiagRecord.decode(<int>[1, 0, 9999, 0]), isNull);
      expect(DiagRecord.decode(<int>[1, 0]), isNull);
    });
  });

  group('persistence and isolate merge', () {
    // FR-16's checkpoint 2 runs in its OWN isolate with its own memory -
    // the static ring buffer there is a different one. The same trap as
    // T-69, just one level deeper. Hence two prefs keys and a merge on
    // read.
    test('main and background isolate end up merged in the export', () async {
      await _freshDiag(isolate: LogIsolate.background);
      Diag.timezoneCheck(
        offsetChanged: true,
        shape: OffsetChangeShape.plusHour,
        valuesConsidered: 7,
        valuesReinterpreted: 6,
      );
      await Diag.flush();

      // Second "start", this time in the main isolate, the same preferences.
      await _freshDiag(clearPrefs: false);
      Diag.alarmRang(
        alarmType: Object,
        knownToAppState: true,
        stale: false,
        deactivationCodeSet: true,
        checkpointFired: true,
      );
      await Diag.flush();

      final all = await Diag.readAll();
      expect(all.map((r) => r.event),
          containsAll(<DiagEvent>[DiagEvent.timezoneCheck, DiagEvent.alarmRang]));
      // Sorted by (boot, seq): the background entry comes from the
      // earlier boot and therefore sits first.
      expect(all.first.event, DiagEvent.timezoneCheck);
      expect(all.first.fields[DiagField.isolate], LogIsolate.background.code);
    });

    test('clear() removes both sinks', () async {
      await _freshDiag();
      Diag.qrGate(outcome: QrOutcome.rejected, codeWasSet: true);
      await Diag.flush();
      expect(await Diag.readAll(), isNotEmpty);

      await Diag.clear();

      expect(await Diag.readAll(), isEmpty);
      expect(Diag.records, isEmpty);
    });
  });

  group('reduction to buckets', () {
    test('the steps match the real bug signatures', () {
      // 0 = healthy
      expect(bucketMinutes(0), MinuteBucket.zero);
      // one hour = offset or DST -> the T-61 signature
      expect(bucketMinutes(60), MinuteBucket.plusHour);
      expect(bucketMinutes(-60), MinuteBucket.minusHour);
      // one day = day off-by-one -> T-74d/T-76
      expect(bucketMinutes(1440), MinuteBucket.plusDay);
      expect(bucketMinutes(-1440), MinuteBucket.minusDay);
      // in between and beyond
      expect(bucketMinutes(5), MinuteBucket.plusFew);
      expect(bucketMinutes(30), MinuteBucket.plusQuarter);
      expect(bucketMinutes(240), MinuteBucket.plusHours);
      expect(bucketMinutes(5000), MinuteBucket.overflow);
    });

    test('the absolute time zone offset is never recorded', () {
      // Only the *shape* of the change. Everyone gets a one-hour change
      // twice a year in a DST country; anything else withholds both
      // magnitude AND sign, so it is worthless as a travel trace.
      expect(bucketOffsetChange(const Duration(hours: 1), const Duration(hours: 2)),
          OffsetChangeShape.plusHour);
      expect(bucketOffsetChange(const Duration(hours: 2), const Duration(hours: 1)),
          OffsetChangeShape.minusHour);
      expect(bucketOffsetChange(const Duration(hours: 1), const Duration(hours: 9)),
          OffsetChangeShape.otherChange);
      expect(bucketOffsetChange(const Duration(hours: 9), const Duration(hours: 1)),
          OffsetChangeShape.otherChange);
      expect(bucketOffsetChange(const Duration(hours: 2), const Duration(hours: 2)),
          OffsetChangeShape.none);
    });

    test('durations are bucketed logarithmically', () {
      expect(bucketMillis(10), DurationBucket.under50);
      expect(bucketMillis(150), DurationBucket.under200);
      expect(bucketMillis(2500), DurationBucket.under3s);
      expect(bucketMillis(60000), DurationBucket.over10s);
    });
  });

  group('export (canary)', () {
    test('the rendered export consists only of enum names and numbers',
        () async {
      await _freshDiag();
      Diag.registerType(_Boom, 7);
      Diag.boot(
        coldStart: true,
        notificationsInitAwaited: true,
        scheduledAlarmCount: 7,
        manualAlarmCount: 1,
        pendingValueCount: 9,
        daysSinceLastReplan: 1,
      );
      Diag.weekPlanComputed(
        todayAlreadyRang: false,
        windowDayCount: 7,
        distinctDayKeys: 7,
        plannedDays: 7,
        nullDays: 0,
        instantAnchoredDays: 1,
        overrunFlag: false,
        safetyValveFlag: false,
        hasPreferredWakeUpTime: true,
        maxStep: MinuteBucket.plusQuarter,
        storedEntriesTotal: 9,
        storedEntriesPruned: 2,
      );
      Diag.failure(
          at: DiagEvent.calendarRead,
          exceptionType: _Boom,
          kind: ErrorKind.plugin);

      final text = Diag.render(Diag.records);

      // Every event line: bN.M [uptime] eventName field=number field=number ...
      final eventLines = text
          .split('\n')
          .where((l) => RegExp(r'^b\d+\.\d+ ').hasMatch(l))
          .toList();
      expect(eventLines.length, 3);
      for (final line in eventLines) {
        expect(
          RegExp(r'^b\d+\.\d+ \[[A-Za-z0-9]+\] [A-Za-z]+( [A-Za-z]+=-?\d+)*( \(bg\))?$')
              .hasMatch(line),
          isTrue,
          reason: 'The export may only contain enum names and numbers - '
              'no free text, no clock time. Line: $line',
        );
      }

      // And explicitly: nothing that looks like a moment or a date.
      expect(RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(text), isFalse);
      expect(RegExp(r'\d{1,2}:\d{2}').hasMatch(text), isFalse);
    });

    test('the header explicitly states what is NOT included', () async {
      // So that a user viewing the export before sharing it has the
      // assertion in black and white.
      await _freshDiag();
      final text = Diag.render(Diag.records);

      expect(text, contains('No timestamps'));
      expect(text, contains('no calendar data'));
    });
  });

  group('clock values only on explicit request (T-135)', () {
    // The rest of the log is constructively free of personal data. A
    // history of wake times and earliest appointment times, on the other
    // hand, is a sleep pattern plus daily routine - identifying without
    // any name - and the log is explicitly exportable via clipboard.
    // Hence a dedicated switch, and hence it defaults to off.

    test('default: dayPlanned writes nothing', () async {
      await _freshDiag();

      expect(Diag.includeClockTimes, isFalse,
          reason: 'the default is the load-bearing assertion');
      Diag.dayPlanned(
          dayOffset: 1, plannedMinuteOfDay: 405, earliestEventMinuteOfDay: 480);

      expect(Diag.records, isEmpty);
    });

    test('when switched on, both numbers are recorded', () async {
      await _freshDiag();
      Diag.setIncludeClockTimes(true);

      // 06:45 planned, earliest appointment 08:00.
      Diag.dayPlanned(
          dayOffset: 2, plannedMinuteOfDay: 405, earliestEventMinuteOfDay: 480);

      expect(Diag.records, hasLength(1));
      final r = Diag.records.single;
      expect(r.event, DiagEvent.dayPlanned);
      expect(r.fields[DiagField.windowDayOffset], 2);
      expect(r.fields[DiagField.plannedMinuteOfDay], 405);
      expect(r.fields[DiagField.earliestEventMinuteOfDay], 480);
    });

    test('"no value"/"no appointment" is -1, not 0', () async {
      // 0 would be midnight and therefore a valid time of day.
      await _freshDiag();
      Diag.setIncludeClockTimes(true);

      Diag.dayPlanned(
          dayOffset: 3, plannedMinuteOfDay: -1, earliestEventMinuteOfDay: -1);

      final r = Diag.records.single;
      expect(r.fields[DiagField.plannedMinuteOfDay], -1);
      expect(r.fields[DiagField.earliestEventMinuteOfDay], -1);
    });

    test('the export itself states whether clock values are in it', () async {
      await _freshDiag();
      expect(Diag.render(Diag.records), contains('no wake times by design'));

      Diag.setIncludeClockTimes(true);
      expect(Diag.render(Diag.records), contains('ARE'),
          reason: 'anyone passing the log along should see it in the header');
    });

    test('the switch does not act as a bypass even when disabled', () async {
      // Counter-check: `includeClockTimes` must not override the main
      // switch.
      await _freshDiag(enabled: false);
      Diag.setIncludeClockTimes(true);

      Diag.dayPlanned(
          dayOffset: 1, plannedMinuteOfDay: 405, earliestEventMinuteOfDay: 480);

      expect(Diag.records, isEmpty);
    });
  });

  group('planning inputs (T-140)', () {
    test('durations are always in, preferredWakeUpTime only with the switch', () async {
      await _freshDiag();
      Diag.planInputs(
          maxDailyDeltaMinutes: 90,
          wakeUpMinutes: 30,
          getReadyMinutes: 0,
          preferredWakeUpMinuteOfDay: 540);

      final r = Diag.records.single;
      expect(r.fields[DiagField.maxDailyDeltaMinutes], 90,
          reason: 'without the cap a logged plan cannot be recomputed');
      expect(r.fields[DiagField.wakeUpMinutes], 30);
      expect(r.fields[DiagField.preferredWakeUpMinuteOfDay], -1,
          reason: 'preferredWakeUpTime is a wake time - only with the switch');
    });

    test('with the switch, preferredWakeUpTime is in too', () async {
      await _freshDiag();
      Diag.setIncludeClockTimes(true);
      Diag.planInputs(
          maxDailyDeltaMinutes: 90,
          wakeUpMinutes: 30,
          getReadyMinutes: 0,
          preferredWakeUpMinuteOfDay: 540);

      expect(Diag.records.single.fields[DiagField.preferredWakeUpMinuteOfDay], 540);
    });
  });
}
