import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

// docs/TODO.md T-89: Verhalten des PII-freien Ereignis-Loggers. Die
// strukturelle Zusicherung (keine String-Parameter) prueft
// test/diag_log_api_test.dart am Quelltext; hier geht es um die Semantik.

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
  group('Ringpuffer', () {
    test('haelt hoechstens `capacity` Ereignisse und verwirft die aeltesten',
        () async {
      await _freshDiag();

      for (var i = 0; i < Diag.capacity + 88; i++) {
        Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);
      }

      expect(Diag.records.length, Diag.capacity);
      // Die ersten 88 sind hinausgerollt: die kleinste noch vorhandene
      // Sequenznummer ist 88.
      expect(Diag.records.first.seq, 88);
      expect(Diag.records.last.seq, Diag.capacity + 87);
    });

    test('abgeschaltet wird nichts aufgezeichnet', () async {
      await _freshDiag(enabled: false);

      Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);
      Diag.failure(
          at: DiagEvent.qrGate, exceptionType: _Boom, kind: ErrorKind.state);

      expect(Diag.records, isEmpty);
    });

    test('jedes Ereignis traegt Boot-Nummer, Sequenz und Isolate', () async {
      await _freshDiag();

      Diag.alarmDismissed(route: DismissRoute.qrScan, stopFailed: false);

      final record = Diag.records.single;
      expect(record.boot, Diag.bootSeq);
      expect(record.seq, 0);
      expect(record.fields[DiagField.isolate], LogIsolate.main.code);
      // Kein Zeitstempel-Feld - nur ein grobes Uptime-Bucket.
      expect(record.uptime, UptimeBucket.firstMinute);
    });

    test('die Boot-Nummer zaehlt ueber App-Starts hinweg hoch', () async {
      await _freshDiag();
      final first = Diag.bootSeq;
      await _freshDiag(clearPrefs: false);

      expect(Diag.bootSeq, first + 1);
    });
  });

  group('Kodierung', () {
    test('encode/decode ist verlustfrei', () async {
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

    test('encode liefert ausschliesslich Zahlen', () async {
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

    test('ein unbekannter Ereigniscode wird beim Dekodieren verworfen', () {
      // Vorwaertskompatibilitaet: ein Log aus einer neueren App-Version darf
      // eine aeltere nicht zum Absturz bringen.
      expect(DiagRecord.decode(<int>[1, 0, 9999, 0]), isNull);
      expect(DiagRecord.decode(<int>[1, 0]), isNull);
    });
  });

  group('Persistenz und Isolate-Merge', () {
    // FR-16s Checkpoint 2 laeuft in einem EIGENEN Isolate mit eigenem
    // Speicher - der statische Ringpuffer dort ist ein anderer. Dieselbe
    // Falle wie T-69, nur eine Ebene tiefer. Deshalb zwei Prefs-Schluessel
    // und ein Merge beim Lesen.
    test('Haupt- und Hintergrund-Isolate landen gemischt im Export', () async {
      await _freshDiag(isolate: LogIsolate.background);
      Diag.timezoneCheck(
        offsetChanged: true,
        shape: OffsetChangeShape.plusHour,
        valuesConsidered: 7,
        valuesReinterpreted: 6,
      );
      await Diag.flush();

      // Zweiter "Start", diesmal im Haupt-Isolate, dieselben Preferences.
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
      // Sortiert nach (boot, seq): der Hintergrund-Eintrag stammt aus dem
      // frueheren Boot und steht deshalb vorn.
      expect(all.first.event, DiagEvent.timezoneCheck);
      expect(all.first.fields[DiagField.isolate], LogIsolate.background.code);
    });

    test('clear() entfernt beide Senken', () async {
      await _freshDiag();
      Diag.qrGate(outcome: QrOutcome.rejected, codeWasSet: true);
      await Diag.flush();
      expect(await Diag.readAll(), isNotEmpty);

      await Diag.clear();

      expect(await Diag.readAll(), isEmpty);
      expect(Diag.records, isEmpty);
    });
  });

  group('Reduktion auf Buckets', () {
    test('die Stufen entsprechen den echten Fehlersignaturen', () {
      // 0 = gesund
      expect(bucketMinutes(0), MinuteBucket.zero);
      // eine Stunde = Versatz oder Sommerzeit -> die T-61-Signatur
      expect(bucketMinutes(60), MinuteBucket.plusHour);
      expect(bucketMinutes(-60), MinuteBucket.minusHour);
      // ein Tag = Tages-Off-by-one -> T-74d/T-76
      expect(bucketMinutes(1440), MinuteBucket.plusDay);
      expect(bucketMinutes(-1440), MinuteBucket.minusDay);
      // dazwischen und darueber
      expect(bucketMinutes(5), MinuteBucket.plusFew);
      expect(bucketMinutes(30), MinuteBucket.plusQuarter);
      expect(bucketMinutes(240), MinuteBucket.plusHours);
      expect(bucketMinutes(5000), MinuteBucket.overflow);
    });

    test('der absolute Zeitzonen-Versatz wird nie abgebildet', () {
      // Nur die *Gestalt* der Aenderung. Eine Stunde bekommt in einem
      // Sommerzeit-Land jeder zweimal im Jahr; alles andere verschweigt
      // Betrag UND Vorzeichen, ist als Reisespur also wertlos.
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

    test('Dauern sind logarithmisch gebucketet', () {
      expect(bucketMillis(10), DurationBucket.under50);
      expect(bucketMillis(150), DurationBucket.under200);
      expect(bucketMillis(2500), DurationBucket.under3s);
      expect(bucketMillis(60000), DurationBucket.over10s);
    });
  });

  group('Export (Canary)', () {
    test('der gerenderte Export besteht nur aus Enum-Namen und Zahlen',
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
        hasWunschzeit: true,
        maxStep: MinuteBucket.plusQuarter,
        storedEntriesTotal: 9,
        storedEntriesPruned: 2,
      );
      Diag.failure(
          at: DiagEvent.calendarRead,
          exceptionType: _Boom,
          kind: ErrorKind.plugin);

      final text = Diag.render(Diag.records);

      // Jede Ereigniszeile: bN.M [uptime] eventName feld=zahl feld=zahl ...
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
          reason: 'Der Export darf nur Enum-Namen und Zahlen enthalten - '
              'kein Freitext, keine Uhrzeit. Zeile: $line',
        );
      }

      // Und explizit: nichts, was nach einem Zeitpunkt oder Datum aussieht.
      expect(RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(text), isFalse);
      expect(RegExp(r'\d{1,2}:\d{2}').hasMatch(text), isFalse);
    });

    test('der Kopf sagt ausdruecklich, was NICHT enthalten ist', () async {
      // Damit ein Nutzer, der den Export vor dem Teilen ansieht, die
      // Zusicherung schwarz auf weiss hat.
      await _freshDiag();
      final text = Diag.render(Diag.records);

      expect(text, contains('No timestamps'));
      expect(text, contains('no calendar data'));
    });
  });
}
