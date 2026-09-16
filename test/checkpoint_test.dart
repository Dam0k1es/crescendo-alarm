import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/notifications.dart';

// docs/TODO.md T-77 + T-80 + T-87: runSchedulingCheckpoint() ist der eine
// Einstiegspunkt für jeden Auslöser (Ring, App-Vordergrund,
// Einstellungsänderung). Vorher gab es fünf Einstiegspunkte, die sich in vier
// orthogonalen Dimensionen unterschieden (Versatz schreiben? heute
// abgeschlossen? melden? Reminder neu planen? Fehler schlucken?) - genau diese
// Matrix hat T-67, T-71 und T-80 produziert, dreimal denselben Fehler in
// derselben Struktur.
//
// Die zwei Eigenschaften, die diese Datei absichert:
//  * T-77: die Sequenz ist serialisiert. Vier Auslöser, drei davon
//    fire-and-forget - und FR-17s Tagessperre konnte sie nicht schützen, weil
//    sie `lastReplanDate` liest, das erst am ENDE von replan() geschrieben
//    wird. Klingelt ein Alarm, holt Android die App per Full-Screen-Intent nach
//    vorn -> zweiter Checkpoint, während der erste noch im Kalender-I/O hängt.
//  * T-80: die Sequenz ist vollständig. scheduleSleepReminder() lief nur aus
//    initState, dem Reminder-Schalter und onAlarmHandled - nicht aus den
//    Checkpoints selbst. Auf dem Resume-Pfad wurde also neu geplant, während
//    die Bettzeit-Notification (FR-16 Checkpoint 2s Aufhänger) auf der alten
//    Zeit stehen blieb.

DateTime _utc(int hour, int minute, {int day = 10}) =>
    DateTime.utc(2026, 3, day, hour, minute);

class _RecordingNotifications implements Notifications {
  _RecordingNotifications({this.observe});

  /// Läuft bei jedem scheduleNotification-Aufruf - so lässt sich prüfen, in
  /// welchem Zustand der AppState zum Zeitpunkt der Benachrichtigung war.
  final void Function()? observe;

  final List<DateTime?> scheduledDates = [];
  final List<int?> ids = [];
  int callCount = 0;
  int cancelAllCount = 0;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    callCount++;
    scheduledDates.add(scheduledDate);
    ids.add(id);
    observe?.call();
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async => cancelAllCount++;

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  group('T-77: Serialisierung', () {
    test(
        'zwei gleichzeitige Vordergrund-Checkpoints zählen den Tag nur einmal fort',
        () async {
      final appState = await _freshAppState();
      // Vorgeschichte: Tag7 ist der letzte verarbeitete Tag. Der Checkpoint
      // läuft als Erholung an Tag9, heute gilt also nicht als abgeschlossen
      // (T-71) - genau ein Tag (Tag8) ist neu zu verarbeiten.
      appState.lastProcessedConcludedDay = _utc(0, 0, day: 7);
      appState.lastReplanDate = _utc(0, 0, day: 7);

      // Der erste Checkpoint hängt im Kalender-I/O, bis wir ihn freigeben -
      // genau das Fenster, in dem der zweite Auslöser hereinkommt.
      final gate = Completer<void>();
      var fetchCount = 0;
      Future<List<Meeting>> slowFetch(DateTime start, DateTime end) async {
        fetchCount++;
        await gate.future;
        return const [];
      }

      final first = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: slowFetch,
        notifications: _RecordingNotifications(),
      );
      // Dem ersten Aufruf Zeit geben, bis in den fetch zu laufen.
      await Future<void>.delayed(Duration.zero);
      final second = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: slowFetch,
        notifications: _RecordingNotifications(),
      );

      gate.complete();
      final results = await Future.wait([first, second]);

      expect(fetchCount, 1,
          reason: 'der zweite Auslöser darf nicht parallel in den Kalender '
              'laufen, bekommen $fetchCount Aufrufe');
      expect(results.where((r) => r != null).length, 1,
          reason: 'genau einer der beiden plant wirklich');
      expect(appState.gapDayCounter, 1,
          reason: 'genau Tag8 ist abgeschlossen und termin-los');
      expect(appState.lastProcessedConcludedDay, _utc(0, 0, day: 8));
    });

    test('eine Einstellungsänderung wartet auf einen laufenden Ring-Checkpoint',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      final gate = Completer<void>();
      final order = <String>[];

      final ring = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async {
          order.add('ring-fetch');
          await gate.future;
          return const [];
        },
        notifications: _RecordingNotifications(),
      );
      await Future<void>.delayed(Duration.zero);

      final settings = runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(8, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async {
          order.add('settings-fetch');
          return const [];
        },
        notifications: _RecordingNotifications(),
      );

      gate.complete();
      await Future.wait([ring, settings]);

      expect(order, ['ring-fetch', 'settings-fetch'],
          reason: 'strikt hintereinander, nicht verschränkt');
      // Eine Einstellungsänderung unterliegt FR-17s Tagessperre NICHT - sie
      // muss also trotz des Rings am selben Tag wirklich neu planen.
      expect(order.contains('settings-fetch'), isTrue);
    });

    test('ein Fehler im ersten Checkpoint blockiert den nächsten nicht',
        () async {
      final appState = await _freshAppState();

      await expectLater(
        runSchedulingCheckpoint(
          appState,
          trigger: CheckpointTrigger.alarmRing,
          now: () => _utc(7, 0, day: 9),
          deviceUtcOffset: Duration.zero,
          fetchEvents: (start, end) async => throw StateError('Kalender kaputt'),
          notifications: _RecordingNotifications(),
        ),
        throwsA(isA<StateError>()),
      );

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(result, isNotNull);
    });
  });

  group('T-80: vollständige Sequenz', () {
    test('der Ring-Checkpoint plant die Bettzeit-Notification neu', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      final notifications = _RecordingNotifications();

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(notifications.callCount, 1);
      expect(notifications.scheduledDates.single, isNotNull);
      expect(notifications.cancelAllCount, 0,
          reason: 'niemals global stornieren (T-74b)');
    });

    test('der Vordergrund-Checkpoint plant sie ebenfalls neu', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      final notifications = _RecordingNotifications();

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(3, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(notifications.callCount, 1);
    });

    test('die Bettzeit wird NACH dem Plan bestimmt, nicht davor', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      var pendingCountAtNotification = -1;
      final notifications = _RecordingNotifications(
        observe: () =>
            pendingCountAtNotification = appState.pendingDayValues.length,
      );

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(pendingCountAtNotification, 7,
          reason: 'der Reminder leitet sich aus dem frischen Plan ab');
    });

    test(
        'FR-17s Tagessperre verhindert beim Vordergrund-Auslöser auch den Reminder-Neuaufbau nicht doppelt',
        () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 9);
      appState.lastProcessedConcludedDay = _utc(0, 0, day: 9);
      final notifications = _RecordingNotifications();

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(9, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: notifications,
      );

      expect(result, isNull, reason: 'FR-17: heute schon geplant -> No-op');
      expect(notifications.callCount, 0,
          reason: 'ohne Neuplanung gibt es auch nichts neu zu terminieren');
    });
  });

  // Portiert aus den entfallenen Einstiegspunkten (runAlarmRingCheckpoint,
  // onAppForegroundCheckpoint, runForegroundCheckpointSafely,
  // onSchedulingSettingsChanged) - die Zusicherungen bleiben, nur der
  // Aufrufweg ist jetzt einheitlich.
  group('FR-16 Checkpoint 1 (Ring)', () {
    test('ein erkannter Versatzwechsel wird persistiert', () async {
      final appState = await _freshAppState();
      appState.lastCheckedUtcOffset = const Duration(hours: 1);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: const Duration(hours: 9),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(appState.lastCheckedUtcOffset, const Duration(hours: 9));
    });

    test('der Ring plant in jedem Fall auch neu (T-61: Instant, nicht Ziffern)',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      appState.lastCheckedUtcOffset = const Duration(hours: 1);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: const Duration(hours: 9),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      // windowStart = Tag11; Kaltstart mit preferredWakeUpTime setzt Tag11 auf 07:00
      // **lokal**. Bei deviceUtcOffset = +9 ist das der Instant 22:00 UTC am
      // Vortag - genau der T-61-Fix (gespeichert wird ein echter Instant,
      // preferredWakeUpTime ist eine geräte-lokale Uhrzeit).
      expect(appState.pendingDayValues['2026-03-11'],
          DateTime.utc(2026, 3, 10, 22, 0).millisecondsSinceEpoch);
      expect(appState.lastReplanDate, _utc(0, 0, day: 10));
    });

    test('unveränderter Versatz lässt den bereits geklingelten Wert unberührt',
        () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      appState.lastCheckedUtcOffset = const Duration(hours: 1);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 9),
        deviceUtcOffset: const Duration(hours: 1),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );
      final fixedValue = appState.pendingDayValues['2026-03-10'];

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: const Duration(hours: 1),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(appState.pendingDayValues['2026-03-10'], fixedValue);
      expect(appState.lastCheckedUtcOffset, const Duration(hours: 1));
    });
  });

  group('FR-17 (App-Vordergrund)', () {
    test('gestern zuletzt geplant -> löst genau einen Checkpoint aus', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 8);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(result, isNotNull);
      expect(appState.lastReplanDate, _utc(0, 0, day: 10));
    });

    test('heute bereits geplant -> gar kein Kalenderzugriff', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 10);
      final pendingBefore = Map.of(appState.pendingDayValues);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async =>
            throw StateError('fetchEvents must not be called'),
        notifications: _RecordingNotifications(),
      );

      expect(result, isNull);
      expect(appState.pendingDayValues, pendingBefore);
    });

    test('Regression: zweiter App-Start direkt nach dem ersten bleibt aus',
        () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 8);

      final first = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );
      expect(first, isNotNull);
      final pendingAfterFirst = Map.of(appState.pendingDayValues);

      final second = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(0, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async =>
            throw StateError('fetchEvents must not be called'),
        notifications: _RecordingNotifications(),
      );

      expect(second, isNull);
      expect(appState.pendingDayValues, pendingAfterFirst);
    });
  });

  group('T-65 (Einstellungsänderung)', () {
    test('plant sofort neu, ohne FR-17s Tagessperre abzuwarten', () async {
      final appState = await _freshAppState();
      appState.lastReplanDate = _utc(0, 0, day: 10);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      final result = await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(result, isNotNull);
      expect(appState.pendingDayValues['2026-03-11'], isNotNull);
    });

    test('ein längeres Schlafziel verschiebt die Bettzeit nach vorn', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      final short = _RecordingNotifications();
      appState.sleepGoal = const TimeOfDay(hour: 6, minute: 0);
      appState.reminderDuration = const TimeOfDay(hour: 0, minute: 0);
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: short,
      );

      final long = _RecordingNotifications();
      appState.sleepGoal = const TimeOfDay(hour: 9, minute: 0);
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: long,
      );

      expect(long.scheduledDates.last!.isBefore(short.scheduledDates.last!),
          isTrue);
    });
  });

  group('runCheckpointSafely', () {
    test('ein fehlschlagender Kalenderzugriff bricht nicht durch', () async {
      final appState = await _freshAppState();

      // Wirft KEINE Exception nach außen - ein durchschlagender Fehler würde
      // hier den App-Start abbrechen bzw. die auslösende UI abstürzen lassen.
      final result = await runCheckpointSafely(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async =>
            throw StateError('calendar plugin unavailable'),
        notifications: _RecordingNotifications(),
      );

      expect(result, isNull);
    });

    test(
        'FR-16s Aufhänger wird selbst dann geplant, wenn die Neuplanung scheitert',
        () async {
      // Sonst hätte ein frischer Install nach einem Kalenderfehler dauerhaft
      // keine Bettzeit-Notification - und damit keinen Checkpoint 2.
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await runCheckpointSafely(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => throw StateError('kaputt'),
        notifications: notifications,
      );

      expect(notifications.callCount, 1);
    });
  });

  // Portiert aus replan_notifications_test.dart: dort war der Meldepfad über
  // injizierte `checkpoint`/`report`-Nähte geprüft, die es nicht mehr gibt.
  // Jetzt geht der Test durch die echte Verdrahtung - stärker als vorher.
  group('T-67: Melden auf dem Erholungspfad (FR-12)', () {
    test('ein verspätet bekannter Termin für einen abgeschlossenen Tag wird gemeldet',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      // Tag9 klingelt, leerer Kalender -> Tag10 auf 07:00 geplant.
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.alarmRing,
        now: () => _utc(7, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      // Tag11, App wird geöffnet: jetzt taucht ein Termin für Tag10 (bereits
      // geklingelt) mit strengerem hardFloor auf.
      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(9, 0, day: 11),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => [
          Meeting(
            from: _utc(5, 0, day: 10),
            to: _utc(6, 0, day: 10),
            isAllDay: false,
            startTimeZone: 'Etc/UTC',
            endTimeZone: 'Etc/UTC',
          )
        ],
        notifications: notifications,
      );

      // Eine FR-12-Meldung plus die Bettzeit-Notification.
      expect(notifications.callCount, 2);
      expect(notifications.ids, contains(isNull),
          reason: 'die FR-12-Warnung läuft ohne feste id');
    });
  });

  group('Auslöser-Semantik', () {
    test('nur der Ring behandelt heute als abgeschlossen (T-71)', () async {
      final appState = await _freshAppState();
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.appForeground,
        now: () => _utc(3, 0, day: 9),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      // Erholung: heute (Tag9) bleibt revidierbar, ist also im Fenster.
      expect(appState.pendingDayValues['2026-03-09'], isNotNull);
    });

    test('jeder Auslöser hält den geprüften Zeitzonen-Versatz fest (FR-16)',
        () async {
      final appState = await _freshAppState();

      await runSchedulingCheckpoint(
        appState,
        trigger: CheckpointTrigger.settingsChanged,
        now: () => _utc(9, 0, day: 9),
        deviceUtcOffset: const Duration(hours: 2),
        fetchEvents: (start, end) async => const [],
        notifications: _RecordingNotifications(),
      );

      expect(appState.lastCheckedUtcOffset, const Duration(hours: 2));
    });
  });
}
