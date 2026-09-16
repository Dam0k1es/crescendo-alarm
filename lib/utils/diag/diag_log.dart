// Ein PII-freier Ereignis-Logger fuer die Entwicklung (docs/TODO.md T-89).
//
// Warum es den ueberhaupt gibt: aus einem installierten Release-Build kam
// bisher NICHTS zurueck. Alle Diagnosen liefen ueber `debugPrint`, und
// `lib/main.dart` ersetzt das im Release durch eine leere Funktion. Ein
// Geraetetest konnte also nur zeigen, DASS etwas schiefging, nie warum.
//
// Warum er keine personenbezogenen Daten erfassen kann - und das ist die
// tragende Entwurfsentscheidung: die Aufzeichnungs-API nimmt **keinen einzigen
// String**. Es gibt damit keinen Kanal, durch den ein Termintitel, ein
// Kalendername, eine Exception-Nachricht oder der QR-Deaktivierungscode
// hineingeraten koennte. Was nicht darstellbar ist, kann nicht austreten.
// `test/diag_log_api_test.dart` prueft diese Eigenschaft am Quelltext nach.
//
// Warum das trotzdem diagnostisch reicht: **jeder** echte Befund dieses
// Projekts war ein STRUKTURfehler, kein WERTfehler - eine falsche Anzahl
// (T-75, T-70), kollidierende Tagesschluessel (T-74d/T-76), ein um genau den
// Geraeteversatz verschobener Wert (T-61), ein Off-by-one-Tag (T-76),
// unbegrenztes Wachstum (T-82), auseinanderlaufende Mengen (T-74e/T-88).
// Keiner davon braucht die tatsaechliche Weckzeit des Nutzers.
//
// Warum keine Uhrzeiten: eine Historie absoluter Weckzeitpunkte plus
// Zeitzonen-Versaetze IST ein Schlafmuster und eine Reisespur - identifizierend
// auch ohne Namen. Deshalb: Tage nur relativ, Zeitpunkte nur als gebucketete
// Differenzen, der absolute Zeitzonen-Versatz nie, Reihenfolge ueber Zaehler
// und Grobzeit ueber `Stopwatch` (monoton, keine Uhrablesung).
//
// Senke: ein begrenzter In-Memory-Ringpuffer, gebuendelt nach
// SharedPreferences. Bewusst nicht in eine Datei ueber `path_provider`: FR-16s
// Checkpoint 2 laeuft in einem Hintergrund-Isolate ohne AppState und redet
// dort schon heute direkt mit SharedPreferences (`runTimezoneCheckpoint2`) -
// ein Datei-Logger haenge dort von der Verfuegbarkeit des Plugin-Channels ab,
// also genau der Fehlerklasse, die T-79 war. Kein Netzcode: die
// Offline-Eigenschaft der App bleibt unberuehrt, der Export laeuft ueber die
// Zwischenablage und damit ausschliesslich auf Nutzerwunsch.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// --------------------------------------------------------------- Ereignisse

/// Jedes Ereignis traegt einen STABILEN Zahlencode. Der Index einer Dart-Enum
/// verschiebt sich beim Umsortieren, ein exportiertes Log muss aber auch von
/// einer anderen App-Version noch lesbar sein.
enum DiagEvent {
  boot(1),
  checkpointStarted(2),
  checkpointSkipped(3),
  checkpointFinished(4),
  calendarRead(10),
  dayAdvance(11),
  weekPlanComputed(12),
  timezoneCheck(13),
  dayPlanned(14),
  planInputs(15),
  alarmSync(20),
  alarmRang(30),
  alarmDismissed(31),
  qrGate(40),
  notificationEmitted(50),
  failure(90);

  const DiagEvent(this.code);
  final int code;
}

/// Feldnamen sind ebenfalls Codes, nicht Strings.
enum DiagField {
  isolate(1),
  // Checkpoint (T-77, T-71, T-80)
  trigger(10),
  queueDepth(11),
  waitBucket(12),
  durationBucket(13),
  outcome(14),
  todayAlreadyRang(15),
  // Tagesfortschreibung und Fenster (T-75, T-74d, T-76, T-82)
  needsDayAdvance(20),
  hadProgressMarker(21),
  daysProcessed(22),
  daysWithHardFloor(23),
  gapCounterBefore(24),
  gapCounterAfter(25),
  missedAppointmentFlagged(26),
  windowDayCount(27),
  distinctDayKeys(28),
  storedEntriesTotal(29),
  storedEntriesPruned(30),
  // Plan (FR-4/6/7/9, T-76, T-78)
  plannedDays(40),
  nullDays(41),
  instantAnchoredDays(42),
  overrunFlag(43),
  safetyValveFlag(44),
  hasPreferredWakeUpTime(45),
  maxStepBucket(46),
  // Kalender (T-70)
  calendarCount(50),
  eventCount(51),
  allDayEventCount(52),
  lazyInitTriggered(53),
  // Zeitzone (FR-16, T-61, T-62)
  offsetChanged(60),
  offsetChangeShape(61),
  valuesConsidered(62),
  valuesReinterpreted(63),
  // FR-18 und Plattform (T-63, T-64, T-74e, T-84, T-88)
  desiredAlarms(70),
  existingAlarms(71),
  platformStateUnknown(72),
  toRemove(73),
  toAdd(74),
  removeFailures(75),
  addFailures(76),
  plannedVsPlatformBucket(77),
  // Klingeln, Abschalten, QR
  alarmTypeCode(80),
  knownToAppState(81),
  stale(82),
  deactivationCodeSet(83),
  checkpointFired(84),
  dismissRoute(85),
  stopFailed(86),
  qrOutcome(87),
  // Meldungen
  notificationKind(90),
  suppressedByEpisodeFlag(91),
  sendFailed(92),
  // Boot
  bootSeq(100),
  coldStart(101),
  notificationsInitAwaited(102),
  scheduledAlarmCount(103),
  manualAlarmCount(104),
  pendingValueCount(105),
  daysSinceLastReplan(106),
  // FR-19-loses Tagesprotokoll (docs/TODO.md T-135). NUR diese drei tragen
  // Uhrwerte, und nur bei ausdruecklich eingeschalteter Zeitprotokollierung.
  // Die EINGABEN einer Planung (docs/TODO.md T-140). Dauern sind keine
  // Uhrzeiten und stehen immer drin; die preferredWakeUpTime ist eine und haengt am
  // Zeit-Schalter.
  maxDailyDeltaMinutes(117),
  wakeUpMinutes(118),
  getReadyMinutes(119),
  windowDayOffset(120),
  plannedMinuteOfDay(121),
  preferredWakeUpMinuteOfDay(123),
  earliestEventMinuteOfDay(122),
  // Fehler
  site(110),
  errorKind(111),
  exceptionTypeCode(112);

  const DiagField(this.code);
  final int code;
}

// ------------------------------------------------------------- Wertdomaenen

/// Dauer einer Operation - logarithmisch, weil die diagnostische Frage
/// "schnell / langsam / haengt" ist, nie "wie viele Millisekunden genau".
enum DurationBucket {
  under50(0),
  under200(1),
  under1s(2),
  under3s(3),
  under10s(4),
  over10s(5);

  const DurationBucket(this.code);
  final int code;
}

/// Signierte Grob-Leiter fuer JEDE Wanduhr-Differenz. Die Stufen sind nach den
/// echten Befunden gewaehlt, nicht nach Bequemlichkeit: 0 = in Ordnung,
/// eine Stunde = Versatz oder Sommerzeit (die T-61-Signatur), ein Tag =
/// Tages-Off-by-one (T-74d/T-76).
enum MinuteBucket {
  minusDay(-6),
  minusHours(-5),
  minusHour(-4),
  minusQuarter(-3),
  minusFew(-2),
  zero(0),
  plusFew(2),
  plusQuarter(3),
  plusHour(4),
  plusHours(5),
  plusDay(6),
  overflow(9);

  const MinuteBucket(this.code);
  final int code;
}

/// Grobe Position im Prozessleben - ersetzt jeden Zeitstempel.
enum UptimeBucket {
  firstMinute(0),
  under5min(1),
  under15min(2),
  under1h(3),
  under6h(4),
  longer(5);

  const UptimeBucket(this.code);
  final int code;
}

enum CheckpointOutcome {
  ok(0),
  replanThrew(1),
  skippedByDailyLock(2);

  const CheckpointOutcome(this.code);
  final int code;
}

enum CalendarOutcome {
  ok(0),
  noCalendars(1),
  initThrew(2),
  retrieveThrew(3),
  partialErrors(4);

  const CalendarOutcome(this.code);
  final int code;
}

/// Der ABSOLUTE Versatz wird nie aufgenommen - er pinnt Zeitzone und damit
/// Region sofort. Diese Form trennt genau die diagnostisch relevante
/// Unterscheidung (Sommerzeit-Gestalt gegen Umzug oder Reise) und ist als
/// Reisespur wertlos: eine Stunde bekommt in einem Sommerzeit-Land jeder
/// zweimal im Jahr, und `otherChange` verschweigt Betrag UND Vorzeichen.
enum OffsetChangeShape {
  none(0),
  plusHour(1),
  minusHour(2),
  otherChange(3);

  const OffsetChangeShape(this.code);
  final int code;
}

enum DismissRoute {
  defaultOverlay(0),
  qrScan(1),
  emergencyStopAll(2),
  staleAutoStop(3),
  unknown(4);

  const DismissRoute(this.code);
  final int code;
}

/// Kein Wert, keine Laenge, kein Hash des Codes - nur das Ergebnis.
enum QrOutcome {
  imported(0),
  accepted(1),
  rejected(2),
  illegalState(3),
  validationThrew(4),
  cameraUnavailable(5);

  const QrOutcome(this.code);
  final int code;
}

enum NotificationKind {
  fr6Overrun(0),
  fr9SafetyValve(1),
  fr12MissedAppointment(2),
  sleepReminderVisible(3),
  sleepReminderSilent(4);

  const NotificationKind(this.code);
  final int code;
}

enum ErrorKind {
  plugin(0),
  decode(1),
  state(2),
  io(3),
  other(4);

  const ErrorKind(this.code);
  final int code;
}

enum LogIsolate {
  main(0),
  background(1);

  const LogIsolate(this.code);
  final int code;
}

/// Welcher Auslöser den Checkpoint angestossen hat. Absichtlich eine eigene
/// Enum und nicht `CheckpointTrigger` aus checkpoint.dart: der Logger soll
/// nicht in die Scheduling-Schicht importieren, und dieser Code muss stabil
/// bleiben, auch wenn dort ein Wert dazukommt.
enum DiagTrigger {
  alarmRing(0),
  appForeground(1),
  settingsChanged(2),
  manualSync(3),
  other(9);

  const DiagTrigger(this.code);
  final int code;
}

// --------------------------------------------------------- Reduktionsstufe

/// Reine Reduktionsfunktionen: sie nehmen einen Rohwert und geben ein Bucket.
/// Der Rohwert erreicht die Senke nie. Bewusst hier und nicht an den
/// Aufrufstellen, damit es genau eine Rundungsregel gibt.
MinuteBucket bucketMinutes(int minutes) {
  final magnitude = minutes.abs();
  if (magnitude == 0) return MinuteBucket.zero;
  if (magnitude > 2880) return MinuteBucket.overflow;

  final MinuteBucket positive;
  if (magnitude >= 1380 && magnitude <= 1500) {
    positive = MinuteBucket.plusDay;
  } else if (magnitude > 180) {
    positive = MinuteBucket.plusHours;
  } else if (magnitude > 45) {
    positive = MinuteBucket.plusHour;
  } else if (magnitude > 15) {
    positive = MinuteBucket.plusQuarter;
  } else {
    positive = MinuteBucket.plusFew;
  }
  if (!minutes.isNegative) return positive;
  return MinuteBucket.values.firstWhere((v) => v.code == -positive.code);
}

DurationBucket bucketMillis(int millis) {
  if (millis < 50) return DurationBucket.under50;
  if (millis < 200) return DurationBucket.under200;
  if (millis < 1000) return DurationBucket.under1s;
  if (millis < 3000) return DurationBucket.under3s;
  if (millis < 10000) return DurationBucket.under10s;
  return DurationBucket.over10s;
}

OffsetChangeShape bucketOffsetChange(Duration before, Duration after) {
  final delta = after.inMinutes - before.inMinutes;
  if (delta == 0) return OffsetChangeShape.none;
  if (delta == 60) return OffsetChangeShape.plusHour;
  if (delta == -60) return OffsetChangeShape.minusHour;
  // Betrag und Vorzeichen bewusst verworfen.
  return OffsetChangeShape.otherChange;
}

// ------------------------------------------------------------------ Record

class DiagRecord {
  const DiagRecord({
    required this.boot,
    required this.seq,
    required this.event,
    required this.uptime,
    required this.fields,
  });

  final int boot;
  final int seq;
  final DiagEvent event;
  final UptimeBucket uptime;
  final Map<DiagField, int> fields;

  /// Die einzige Stelle, an der ein Record die In-Memory-Struktur verlaesst -
  /// als reine Zahlenliste, damit kein Freitext in die Senke gelangen kann.
  List<int> encode() => <int>[
        boot,
        seq,
        event.code,
        uptime.code,
        for (final entry in fields.entries) ...[entry.key.code, entry.value],
      ];

  static DiagRecord? decode(List<dynamic> raw) {
    if (raw.length < 4 || raw.length.isOdd) return null;
    final event = DiagEvent.values.where((e) => e.code == raw[2]).firstOrNull;
    final uptime =
        UptimeBucket.values.where((u) => u.code == raw[3]).firstOrNull;
    if (event == null || uptime == null) return null;
    final fields = <DiagField, int>{};
    for (var i = 4; i + 1 < raw.length; i += 2) {
      final field = DiagField.values.where((f) => f.code == raw[i]).firstOrNull;
      if (field != null) fields[field] = raw[i + 1] as int;
    }
    return DiagRecord(
      boot: raw[0] as int,
      seq: raw[1] as int,
      event: event,
      uptime: uptime,
      fields: fields,
    );
  }
}

// -------------------------------------------------------------------- Kern

abstract final class Diag {
  /// Gebunden, nicht wachsend - die Lehre aus T-82. Doppelt wirksam: es frisst
  /// keinen Speicher, UND aus dem Log laesst sich kein Langzeitprofil gewinnen.
  static const int capacity = 512;

  static const String prefsKeyMain = 'diagLogMain';
  static const String prefsKeyIsolate = 'diagLogIsolate';
  static const String prefsKeyBootSeq = 'diagBootSeq';

  static final List<DiagRecord> _ring = <DiagRecord>[];
  static final Stopwatch _uptime = Stopwatch()..start();
  static SharedPreferences? _prefs;
  static LogIsolate _isolate = LogIsolate.main;
  static int _boot = 0;
  static int _seq = 0;
  static bool _enabled = true;
  static bool _dirty = false;

  /// `Type` wird ueber eine Identitaetstabelle auf einen Code abgebildet.
  /// `toString()` wird auf einem Type NIE gerufen: unter R8-Obfuskierung waere
  /// der Name ohnehin Muell, und so entsteht auch hier kein String.
  static final Map<Type, int> _typeCodes = <Type, int>{};

  static void registerType(Type type, int code) => _typeCodes[type] = code;

  static int typeCode(Type type) => _typeCodes[type] ?? 0;

  static bool get enabled => _enabled;
  static int get bootSeq => _boot;
  static List<DiagRecord> get records => List.unmodifiable(_ring);

  static Future<void> init({
    LogIsolate isolate = LogIsolate.main,
    bool enabled = true,
    SharedPreferences? prefs,
  }) async {
    _isolate = isolate;
    _enabled = enabled;
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _boot = (_prefs!.getInt(prefsKeyBootSeq) ?? 0) + 1;
    await _prefs!.setInt(prefsKeyBootSeq, _boot);
  }

  static void setEnabled(bool value) => _enabled = value;

  /// Schreibt [dayPlanned] ueberhaupt Uhrwerte? Standard **aus**.
  ///
  /// Getrennt von [setEnabled] mit Absicht: das uebrige Log ist konstruktiv
  /// frei von personenbezogenen Daten, und das soll die Vorgabe bleiben. Eine
  /// Historie aus Weckzeiten und fruehesten Terminzeiten ist dagegen ein
  /// Schlafmuster samt Tagesablauf - identifizierend ohne jeden Namen, und das
  /// Log ist ausdruecklich per Zwischenablage exportierbar. Wer es einschaltet,
  /// tut das fuer die eigene Fehlersuche und weiss, was er weitergibt.
  static bool _includeClockTimes = false;
  static void setIncludeClockTimes(bool value) => _includeClockTimes = value;
  static bool get includeClockTimes => _includeClockTimes;

  /// Nur fuer Tests: setzt den Prozesszustand zurueck.
  static void resetForTest() {
    _ring.clear();
    _seq = 0;
    _boot = 0;
    _dirty = false;
    _enabled = true;
    // Muss mit zurueckgesetzt werden, sonst leckt der Schalter zwischen Tests
    // (docs/TODO.md T-135): ein Test, der ihn einschaltet, haette sonst den
    // naechsten beeinflusst - dieselbe Falle mit globalem Zustand, die T-89
    // schon einmal gestellt hat.
    _includeClockTimes = false;
    _isolate = LogIsolate.main;
    _typeCodes.clear();
    _prefs = null;
  }

  static void _record(DiagEvent event, Map<DiagField, int> fields) {
    if (!_enabled) return;
    if (_ring.length >= capacity) _ring.removeAt(0);
    _ring.add(DiagRecord(
      boot: _boot,
      seq: _seq++,
      event: event,
      uptime: _bucketUptime(_uptime.elapsed.inSeconds),
      fields: <DiagField, int>{DiagField.isolate: _isolate.code, ...fields},
    ));
    _dirty = true;
  }

  static UptimeBucket _bucketUptime(int seconds) {
    if (seconds < 60) return UptimeBucket.firstMinute;
    if (seconds < 300) return UptimeBucket.under5min;
    if (seconds < 900) return UptimeBucket.under15min;
    if (seconds < 3600) return UptimeBucket.under1h;
    if (seconds < 21600) return UptimeBucket.under6h;
    return UptimeBucket.longer;
  }

  /// Gebuendelt persistieren, nicht pro Ereignis - der Klingelpfad darf keine
  /// I/O-Latenz bekommen. Aufrufer: Checkpoint-Ende, App-Pause, Boot.
  static Future<void> flush() async {
    final prefs = _prefs;
    if (!_dirty || prefs == null) return;
    final key = _isolate == LogIsolate.main ? prefsKeyMain : prefsKeyIsolate;
    await prefs.setString(
        key, jsonEncode(_ring.map((r) => r.encode()).toList()));
    _dirty = false;
  }

  /// Liest beide Senken und mischt sie nach (boot, seq).
  ///
  /// Zwei Schluessel sind noetig, weil FR-16s Checkpoint 2 in einem eigenen
  /// Isolate mit eigenem Speicher laeuft - der statische Ringpuffer dort ist
  /// ein ANDERER. Dieselbe Falle wie T-69, nur eine Ebene tiefer.
  static Future<List<DiagRecord>> readAll({SharedPreferences? prefs}) async {
    final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
    final all = <DiagRecord>[];
    for (final key in <String>[prefsKeyMain, prefsKeyIsolate]) {
      final raw = p.getString(key);
      if (raw == null) continue;
      try {
        for (final entry in jsonDecode(raw) as List<dynamic>) {
          final record = DiagRecord.decode(entry as List<dynamic>);
          if (record != null) all.add(record);
        }
      } catch (_) {
        // Ein beschaedigter Eintrag darf den Export nicht verhindern. Bewusst
        // ohne Ausgabe: die Ausnahme selbst koennte die Quellzeichenkette
        // enthalten (die Fehlerklasse aus T-89).
      }
    }
    all.sort((a, b) {
      final byBoot = a.boot.compareTo(b.boot);
      return byBoot != 0 ? byBoot : a.seq.compareTo(b.seq);
    });
    return all;
  }

  static Future<void> clear({SharedPreferences? prefs}) async {
    final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
    _ring.clear();
    _dirty = false;
    await p.remove(prefsKeyMain);
    await p.remove(prefsKeyIsolate);
  }

  /// Menschenlesbare Darstellung fuer den Export. Die Namen kommen aus den
  /// Enums dieser Datei, also aus dem Programm selbst - nie aus Nutzerdaten.
  static String render(List<DiagRecord> records) {
    final out = StringBuffer()
      ..writeln('WakeyWakey diagnostics (${records.length} events)')
      ..writeln(_includeClockTimes
          ? 'No timestamps. Wake times and earliest appointment times ARE '
              'included (dayPlanned) because clock logging is switched on.'
          : 'No timestamps, no calendar data, no wake times by design.')
      ..writeln();
    for (final r in records) {
      out.write('b${r.boot}.${r.seq} [${r.uptime.name}] ${r.event.name}');
      for (final entry in r.fields.entries) {
        if (entry.key == DiagField.isolate) continue;
        out.write(' ${entry.key.name}=${entry.value}');
      }
      if (r.fields[DiagField.isolate] == LogIsolate.background.code) {
        out.write(' (bg)');
      }
      out.writeln();
    }
    return out.toString();
  }

  // == PUBLIC RECORDING API ==
  //
  // Nur Enums, `int` (Zaehlungen und RELATIVE Tage), `bool` und `Type`.
  // Kein String - an keiner Stelle. `_record` ist privat, damit an keiner
  // Aufrufstelle ein Feld improvisiert werden kann; die Signatur IST das
  // Schema.

  static void boot({
    required bool coldStart,
    required bool notificationsInitAwaited,
    required int scheduledAlarmCount,
    required int manualAlarmCount,
    required int pendingValueCount,
    required int daysSinceLastReplan,
  }) =>
      _record(DiagEvent.boot, <DiagField, int>{
        DiagField.bootSeq: _boot,
        DiagField.coldStart: coldStart ? 1 : 0,
        DiagField.notificationsInitAwaited: notificationsInitAwaited ? 1 : 0,
        DiagField.scheduledAlarmCount: scheduledAlarmCount,
        DiagField.manualAlarmCount: manualAlarmCount,
        DiagField.pendingValueCount: pendingValueCount,
        DiagField.daysSinceLastReplan: daysSinceLastReplan,
      });

  static void checkpointStarted({
    required DiagTrigger trigger,
    required int queueDepth,
    required DurationBucket waited,
  }) =>
      _record(DiagEvent.checkpointStarted, <DiagField, int>{
        DiagField.trigger: trigger.code,
        DiagField.queueDepth: queueDepth,
        DiagField.waitBucket: waited.code,
      });

  static void checkpointSkipped({
    required DiagTrigger trigger,
    required int daysSinceLastReplan,
  }) =>
      _record(DiagEvent.checkpointSkipped, <DiagField, int>{
        DiagField.trigger: trigger.code,
        DiagField.outcome: CheckpointOutcome.skippedByDailyLock.code,
        DiagField.daysSinceLastReplan: daysSinceLastReplan,
      });

  static void checkpointFinished({
    required DiagTrigger trigger,
    required CheckpointOutcome outcome,
    required DurationBucket took,
  }) =>
      _record(DiagEvent.checkpointFinished, <DiagField, int>{
        DiagField.trigger: trigger.code,
        DiagField.outcome: outcome.code,
        DiagField.durationBucket: took.code,
      });

  static void calendarRead({
    required CalendarOutcome outcome,
    required int calendarCount,
    required int eventCount,
    required int allDayEventCount,
    required bool lazyInitTriggered,
    required DurationBucket took,
  }) =>
      _record(DiagEvent.calendarRead, <DiagField, int>{
        DiagField.outcome: outcome.code,
        DiagField.calendarCount: calendarCount,
        DiagField.eventCount: eventCount,
        DiagField.allDayEventCount: allDayEventCount,
        DiagField.lazyInitTriggered: lazyInitTriggered ? 1 : 0,
        DiagField.durationBucket: took.code,
      });

  /// T-75 haette hier sofort ins Auge gesprungen: `daysProcessed = 0` an einem
  /// Tag, an dem der Wecker geklingelt hat.
  static void dayAdvance({
    required bool needsDayAdvance,
    required bool hadProgressMarker,
    required int daysProcessed,
    required int daysWithHardFloor,
    required int gapCounterBefore,
    required int gapCounterAfter,
    required bool missedAppointmentFlagged,
  }) =>
      _record(DiagEvent.dayAdvance, <DiagField, int>{
        DiagField.needsDayAdvance: needsDayAdvance ? 1 : 0,
        DiagField.hadProgressMarker: hadProgressMarker ? 1 : 0,
        DiagField.daysProcessed: daysProcessed,
        DiagField.daysWithHardFloor: daysWithHardFloor,
        DiagField.gapCounterBefore: gapCounterBefore,
        DiagField.gapCounterAfter: gapCounterAfter,
        DiagField.missedAppointmentFlagged: missedAppointmentFlagged ? 1 : 0,
      });

  /// `windowDayCount != distinctDayKeys` ist die Signatur von T-74d/T-76:
  /// zwei Fenstertage sind auf denselben Tagesschluessel kollidiert.
  static void weekPlanComputed({
    required bool todayAlreadyRang,
    required int windowDayCount,
    required int distinctDayKeys,
    required int plannedDays,
    required int nullDays,
    required int instantAnchoredDays,
    required bool overrunFlag,
    required bool safetyValveFlag,
    required bool hasPreferredWakeUpTime,
    required MinuteBucket maxStep,
    required int storedEntriesTotal,
    required int storedEntriesPruned,
  }) =>
      _record(DiagEvent.weekPlanComputed, <DiagField, int>{
        DiagField.todayAlreadyRang: todayAlreadyRang ? 1 : 0,
        DiagField.windowDayCount: windowDayCount,
        DiagField.distinctDayKeys: distinctDayKeys,
        DiagField.plannedDays: plannedDays,
        DiagField.nullDays: nullDays,
        DiagField.instantAnchoredDays: instantAnchoredDays,
        DiagField.overrunFlag: overrunFlag ? 1 : 0,
        DiagField.safetyValveFlag: safetyValveFlag ? 1 : 0,
        DiagField.hasPreferredWakeUpTime: hasPreferredWakeUpTime ? 1 : 0,
        DiagField.maxStepBucket: maxStep.code,
        DiagField.storedEntriesTotal: storedEntriesTotal,
        DiagField.storedEntriesPruned: storedEntriesPruned,
      });

  /// FR-16 Checkpoint 2. Beantwortet auch T-62 ("feuert die stille
  /// Notification den Callback ueberhaupt?") - wenn dieses Ereignis im Export
  /// auftaucht, ist die Antwort ja.
  static void timezoneCheck({
    required bool offsetChanged,
    required OffsetChangeShape shape,
    required int valuesConsidered,
    required int valuesReinterpreted,
  }) =>
      _record(DiagEvent.timezoneCheck, <DiagField, int>{
        DiagField.offsetChanged: offsetChanged ? 1 : 0,
        DiagField.offsetChangeShape: shape.code,
        DiagField.valuesConsidered: valuesConsidered,
        DiagField.valuesReinterpreted: valuesReinterpreted,
      });

  /// T-64 waere hier als `toRemove` gross und `toAdd = 0` sichtbar gewesen;
  /// T-61 als `plannedVsPlatform` genau eine Stunde.
  static void alarmSync({
    required int desiredAlarms,
    required int existingAlarms,
    required bool platformStateUnknown,
    required int toRemove,
    required int toAdd,
    required int removeFailures,
    required int addFailures,
    required MinuteBucket plannedVsPlatform,
  }) =>
      _record(DiagEvent.alarmSync, <DiagField, int>{
        DiagField.desiredAlarms: desiredAlarms,
        DiagField.existingAlarms: existingAlarms,
        DiagField.platformStateUnknown: platformStateUnknown ? 1 : 0,
        DiagField.toRemove: toRemove,
        DiagField.toAdd: toAdd,
        DiagField.removeFailures: removeFailures,
        DiagField.addFailures: addFailures,
        DiagField.plannedVsPlatformBucket: plannedVsPlatform.code,
      });

  static void alarmRang({
    required Type alarmType,
    required bool knownToAppState,
    required bool stale,
    required bool deactivationCodeSet,
    required bool checkpointFired,
  }) =>
      _record(DiagEvent.alarmRang, <DiagField, int>{
        DiagField.alarmTypeCode: typeCode(alarmType),
        DiagField.knownToAppState: knownToAppState ? 1 : 0,
        DiagField.stale: stale ? 1 : 0,
        DiagField.deactivationCodeSet: deactivationCodeSet ? 1 : 0,
        DiagField.checkpointFired: checkpointFired ? 1 : 0,
      });

  static void alarmDismissed({
    required DismissRoute route,
    required bool stopFailed,
  }) =>
      _record(DiagEvent.alarmDismissed, <DiagField, int>{
        DiagField.dismissRoute: route.code,
        DiagField.stopFailed: stopFailed ? 1 : 0,
      });

  /// Kein Parameter fuer den Payload. Auch keiner fuer dessen Laenge oder
  /// Hash - beides waere ein Rueckweg zum Geheimnis.
  static void qrGate({
    required QrOutcome outcome,
    required bool codeWasSet,
  }) =>
      _record(DiagEvent.qrGate, <DiagField, int>{
        DiagField.qrOutcome: outcome.code,
        DiagField.deactivationCodeSet: codeWasSet ? 1 : 0,
      });

  static void notificationEmitted({
    required NotificationKind kind,
    required bool suppressedByEpisodeFlag,
    required bool sendFailed,
  }) =>
      _record(DiagEvent.notificationEmitted, <DiagField, int>{
        DiagField.notificationKind: kind.code,
        DiagField.suppressedByEpisodeFlag: suppressedByEpisodeFlag ? 1 : 0,
        DiagField.sendFailed: sendFailed ? 1 : 0,
      });

  /// Der Ersatz fuer jedes `catch (e)`, das eine Ausnahme in ein Log schrieb:
  /// die Ausnahme geht als `runtimeType` und Kategorie ein, nie als Nachricht.
  /// `FormatException.toString()` echot einen Ausschnitt der
  /// Quellzeichenkette - genau darueber sind in T-89 Nutzdaten ausgetreten.
  /// A single window day: the planned wake time and the day's earliest
  /// appointment, both as a minute of the local day (0..1439), `-1` for
  /// "none" (docs/TODO.md T-135).
  ///
  /// **The only event carrying clock values.** It writes only while
  /// [setIncludeClockTimes] is on; otherwise it is a no-op. Built for exactly
  /// the question the rest of the log cannot answer: *why* does a given day
  /// carry this wake time - is it the appointment, the curve, or the
  /// preferred wake-up time? Counts and buckets alone cannot reconstruct
  /// that; with these two numbers a week's plan can be recomputed by hand.
  ///
  /// [dayOffset] stays relative (as everywhere in the log), and the minutes
  /// deliberately carry NO date - no calendar day can be derived from them.
  static void dayPlanned({
    required int dayOffset,
    required int plannedMinuteOfDay,
    required int earliestEventMinuteOfDay,
  }) {
    if (!_includeClockTimes) return;
    _record(DiagEvent.dayPlanned, <DiagField, int>{
      DiagField.windowDayOffset: dayOffset,
      DiagField.plannedMinuteOfDay: plannedMinuteOfDay,
      DiagField.earliestEventMinuteOfDay: earliestEventMinuteOfDay,
    });
  }

  /// Die Eingaben, aus denen ein Wochenplan entsteht (docs/TODO.md T-140).
  ///
  /// Ohne sie ist ein geloggter Plan nicht nachrechenbar: `maxStepBucket` sagt,
  /// wie gross der groesste Schritt WAR, aber nicht, wie gross er sein DURFTE.
  /// Beim ersten echten Geraete-Log musste das Limit aus den Schrittweiten
  /// zurueckgerechnet werden - und der Maintainer hatte es zwischendurch
  /// geaendert, was aus dem Log nicht hervorging.
  ///
  /// Dauern sind keine Uhrzeiten: "90 Minuten Grenze" verraet nichts ueber
  /// Schlaf. Die `preferredWakeUpTime` dagegen ist eine Weckzeit und steht nur bei
  /// eingeschalteter Zeitprotokollierung drin, sonst `-1`.
  static void planInputs({
    required int maxDailyDeltaMinutes,
    required int wakeUpMinutes,
    required int getReadyMinutes,
    required int preferredWakeUpMinuteOfDay,
  }) =>
      _record(DiagEvent.planInputs, <DiagField, int>{
        DiagField.maxDailyDeltaMinutes: maxDailyDeltaMinutes,
        DiagField.wakeUpMinutes: wakeUpMinutes,
        DiagField.getReadyMinutes: getReadyMinutes,
        DiagField.preferredWakeUpMinuteOfDay:
            _includeClockTimes ? preferredWakeUpMinuteOfDay : -1,
      });

  static void failure({
    required DiagEvent at,
    required Type exceptionType,
    required ErrorKind kind,
  }) =>
      _record(DiagEvent.failure, <DiagField, int>{
        DiagField.site: at.code,
        DiagField.exceptionTypeCode: typeCode(exceptionType),
        DiagField.errorKind: kind.code,
      });
}
