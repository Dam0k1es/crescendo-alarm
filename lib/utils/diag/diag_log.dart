// A PII-free event logger for development (docs/TODO.md T-89).
//
// Why it exists at all: nothing at all came back from an installed release
// build. Every diagnostic went through `debugPrint`, and `lib/main.dart`
// replaces that with an empty function in release. A device test could
// therefore only show THAT something went wrong, never why.
//
// Why it structurally cannot record personal data - and this is the
// load-bearing design decision: the recording API takes **not a single
// String**. There is therefore no channel through which an appointment
// title, a calendar name, an exception message, or the QR deactivation code
// could enter it. What cannot be represented cannot leak.
// `test/diag_log_api_test.dart` checks this property against the source.
//
// Why this is still diagnostically sufficient: **every** real finding in
// this project was a STRUCTURAL bug, not a VALUE bug - a wrong count (T-75,
// T-70), colliding day keys (T-74d/T-76), a value shifted by exactly the
// device offset (T-61), an off-by-one day (T-76), unbounded growth (T-82),
// diverging sets (T-74e/T-88). None of them needs the user's actual wake
// time.
//
// Why no clock times: a history of absolute wake instants plus time zone
// offsets IS a sleep pattern and a travel trace - identifying even without a
// name. Hence: days only relative, instants only as bucketed differences,
// the absolute time zone offset never, ordering via a counter, and coarse
// timing via `Stopwatch` (monotonic, no clock read).
//
// Sink: a bounded in-memory ring buffer, batched to SharedPreferences.
// Deliberately not a file via `path_provider`: FR-16's checkpoint 2 runs in
// a background isolate with no AppState and already talks directly to
// SharedPreferences there today (`runTimezoneCheckpoint2`) - a file logger
// there would depend on the plugin channel's availability, exactly the bug
// class T-79 was. No network code: the app's offline property stays
// untouched, and export goes via the clipboard, and thus only ever at the
// user's own request.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ------------------------------------------------------------------ Events

/// Every event carries a STABLE numeric code. A Dart enum's index shifts
/// when reordered, but an exported log must still be readable by a
/// different app version.
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

/// Field names are also codes, not strings.
enum DiagField {
  isolate(1),
  // Checkpoint (T-77, T-71, T-80)
  trigger(10),
  queueDepth(11),
  waitBucket(12),
  durationBucket(13),
  outcome(14),
  todayAlreadyRang(15),
  // Day-advance and the window (T-75, T-74d, T-76, T-82)
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
  // Calendar (T-70)
  calendarCount(50),
  eventCount(51),
  allDayEventCount(52),
  lazyInitTriggered(53),
  // Time zone (FR-16, T-61, T-62)
  offsetChanged(60),
  offsetChangeShape(61),
  valuesConsidered(62),
  valuesReinterpreted(63),
  // FR-18 and the platform (T-63, T-64, T-74e, T-84, T-88)
  desiredAlarms(70),
  existingAlarms(71),
  platformStateUnknown(72),
  toRemove(73),
  toAdd(74),
  removeFailures(75),
  addFailures(76),
  plannedVsPlatformBucket(77),
  // Ringing, dismissal, QR
  alarmTypeCode(80),
  knownToAppState(81),
  stale(82),
  deactivationCodeSet(83),
  checkpointFired(84),
  dismissRoute(85),
  stopFailed(86),
  qrOutcome(87),
  // Notifications
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
  // The FR-19-less daily log (docs/TODO.md T-135). ONLY these three carry
  // clock values, and only when clock-time logging has been explicitly
  // switched on. The INPUTS of a planning run (docs/TODO.md T-140).
  // Durations are not times of day and are always included; preferredWakeUpTime
  // is one and is gated behind the clock-time switch.
  maxDailyDeltaMinutes(117),
  wakeUpMinutes(118),
  getReadyMinutes(119),
  windowDayOffset(120),
  plannedMinuteOfDay(121),
  preferredWakeUpMinuteOfDay(123),
  earliestEventMinuteOfDay(122),
  // Errors
  site(110),
  errorKind(111),
  exceptionTypeCode(112);

  const DiagField(this.code);
  final int code;
}

// ------------------------------------------------------------- Value domains

/// Duration of an operation - logarithmic, because the diagnostic question
/// is "fast / slow / hanging", never "how many milliseconds exactly".
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

/// A signed coarse ladder for ANY wall-clock difference. The steps are
/// chosen after the real findings, not for convenience: 0 = healthy,
/// one hour = offset or daylight saving (the T-61 signature), one day =
/// a day off-by-one (T-74d/T-76).
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

/// A coarse position in the process's lifetime - replaces every timestamp.
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

/// The ABSOLUTE offset is never recorded - it would pin down the time zone,
/// and thus the region, immediately. This shape draws exactly the
/// diagnostically relevant distinction (a daylight-saving shape versus a
/// move or a trip) and is worthless as a travel trace: everyone in a
/// daylight-saving country gets a one-hour shift twice a year, and
/// `otherChange` withholds both the amount and the sign.
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

/// No value, no length, no hash of the code - only the outcome.
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

/// Which trigger kicked off the checkpoint. Deliberately its own enum, not
/// `CheckpointTrigger` from checkpoint.dart: the logger should not import the
/// scheduling layer, and this code must stay stable even if a value is added
/// there.
enum DiagTrigger {
  alarmRing(0),
  appForeground(1),
  settingsChanged(2),
  manualSync(3),
  other(9);

  const DiagTrigger(this.code);
  final int code;
}

// ------------------------------------------------------------- Bucketing

/// Pure reduction functions: they take a raw value and return a bucket. The
/// raw value never reaches the sink. Deliberately here and not at the call
/// sites, so there is exactly one rounding rule.
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
  // Amount and sign deliberately discarded.
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

  /// The only place a record leaves the in-memory structure - as a plain
  /// list of numbers, so no free text can ever reach the sink.
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

// --------------------------------------------------------------------- Core

abstract final class Diag {
  /// Bounded, not growing - the lesson from T-82. Doubly effective: it
  /// doesn't eat memory, AND no long-term profile can be built from the log.
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

  /// A `Type` is mapped to a code via an identity table. `toString()` is
  /// NEVER called on a Type: under R8 obfuscation the name would be garbage
  /// anyway, and this way no String is produced here either.
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

  /// Does [dayPlanned] record clock values at all? Default **off**.
  ///
  /// Deliberately separate from [setEnabled]: the rest of the log is
  /// structurally free of personal data, and that should stay the default.
  /// A history of wake times and earliest appointment times, by contrast, is
  /// a sleep pattern with a daily routine - identifying with no name at all,
  /// and the log is explicitly exportable via the clipboard. Whoever
  /// switches this on does so for their own troubleshooting and knows what
  /// they're passing on.
  static bool _includeClockTimes = false;
  static void setIncludeClockTimes(bool value) => _includeClockTimes = value;
  static bool get includeClockTimes => _includeClockTimes;

  /// Test-only: resets the process-level state.
  static void resetForTest() {
    _ring.clear();
    _seq = 0;
    _boot = 0;
    _dirty = false;
    _enabled = true;
    // Must be reset along with the rest, or the switch leaks between tests
    // (docs/TODO.md T-135): a test that switches it on would otherwise
    // affect the next one - the same global-state trap T-89 already set
    // once.
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

  /// Persisted in a batch, not per event - the ring path must not get any
  /// I/O latency. Callers: checkpoint end, app pause, boot.
  static Future<void> flush() async {
    final prefs = _prefs;
    if (!_dirty || prefs == null) return;
    final key = _isolate == LogIsolate.main ? prefsKeyMain : prefsKeyIsolate;
    await prefs.setString(
        key, jsonEncode(_ring.map((r) => r.encode()).toList()));
    _dirty = false;
  }

  /// Reads both sinks and merges them by (boot, seq).
  ///
  /// Two keys are needed because FR-16's checkpoint 2 runs in its own
  /// isolate with its own memory - the static ring buffer there is a
  /// DIFFERENT one. The same trap as T-69, just one level deeper.
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
        // A corrupted entry must not prevent the export. Deliberately no
        // output: the exception itself could contain the source string
        // (the bug class from T-89).
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

  /// A human-readable rendering for export. The names come from this file's
  /// own enums, i.e. from the program itself - never from user data.
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
  // Only enums, `int` (counts and RELATIVE days), `bool`, and `Type`. No
  // String - anywhere. `_record` is private so no call site can improvise a
  // field; the signature IS the schema.

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

  /// T-75 would have jumped out here immediately: `daysProcessed = 0` on a
  /// day the alarm rang.
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

  /// `windowDayCount != distinctDayKeys` is the signature of T-74d/T-76:
  /// two window days collided on the same day key.
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

  /// FR-16 checkpoint 2. Also answers T-62 ("does the silent notification
  /// even trigger the callback?") - if this event shows up in the export,
  /// the answer is yes.
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

  /// T-64 would have been visible here as a large `toRemove` with
  /// `toAdd = 0`; T-61 as `plannedVsPlatform` exactly one hour off.
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

  /// No parameter for the payload. None for its length or a hash either -
  /// both would be a way back to the secret.
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

  /// The inputs a week plan is computed from (docs/TODO.md T-140).
  ///
  /// Without them a logged plan can't be checked by recomputation:
  /// `maxStepBucket` says how big the largest step WAS, but not how big it
  /// was ALLOWED to be. On the first real device log, the limit had to be
  /// reverse-engineered from the step sizes - and the maintainer had changed
  /// it partway through, which the log didn't show at all.
  ///
  /// Durations are not times of day: "90-minute limit" reveals nothing about
  /// sleep. `preferredWakeUpTime`, by contrast, is a wake time and is only
  /// included when clock-time logging is switched on, otherwise `-1`.
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

  /// The replacement for every `catch (e)` that wrote an exception into a
  /// log: the exception goes in as `runtimeType` and category, never as a
  /// message. `FormatException.toString()` echoes a slice of the source
  /// string - exactly that is how payload data leaked in T-89.
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
