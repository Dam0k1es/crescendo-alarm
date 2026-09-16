// Real end-to-end tests, driven against a real (emulated or physical)
// Android device via `flutter test integration_test/` (or `flutter drive`).
// These exercise the actual native `alarm` plugin - alarms really fire via
// the OS. Scenario 3's persistence check currently reads an in-process
// SharedPreferences cache rather than a genuine on-device storage round-trip
// (see docs/TODO.md T-04) - it does not yet prove what its name suggests.
//
// Prerequisites (see .github/workflows for how CI sets these up):
// - All dangerous permissions pre-granted via `adb shell pm grant` /
//   `adb shell appops set`, so the in-app permission flow completes without
//   needing to interact with OS dialogs.
// - Covers the first three items of the E2E test plan in docs/TODO.md (see
//   also docs/REQUIREMENTS.md R3/R4). A fourth item, stale alarm auto-stop,
//   is a pure-logic test covered separately in
//   test/handler_stale_alarm_test.dart instead, since it needs no device/UI.
//
// Scope note: scenario 2 (QR deactivation) injects the scan result via
// QrScanner.debugBarcodeStreamOverride rather than actually feeding camera
// data - see that field's doc comment in lib/screens/scan_code/qr_scanner.dart
// and docs/TODO.md T-16 for why, and what that does and doesn't prove.

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/main.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/alarms/screen_active_alarm.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/utils.dart';

/// Repeatedly pumps [tester] until [finder] matches something, or [timeout]
/// elapses. Unlike `pumpAndSettle`, this is safe to use while waiting on a
/// real, slow, external event (like a native alarm actually ringing).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
  Duration step = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out after $timeout waiting for $finder to appear');
}

/// The inverse of [pumpUntilFound] - waits for [finder] to stop matching
/// anything.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
  Duration step = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  fail('Timed out after $timeout waiting for $finder to disappear');
}

Future<AppState> pumpFreshApp(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MyApp(),
    ),
  );

  // Permissions were pre-granted via adb before the test run, so the splash
  // screen's permission check resolves quickly - just wait for MyHomePage.
  await pumpUntilFound(tester, find.byType(MyHomePage),
      timeout: const Duration(seconds: 30));
  await tester.pumpAndSettle();

  return appState;
}

/// Creates a manual alarm ~1 minute from now via the real UI flow (the "add
/// alarm" dialog defaults to now+1 minute, so no time-picker interaction is
/// needed) and returns to the Alarms tab.
///
/// Fails fast with a clear message if the alarm that was actually scheduled
/// lands far from "now + 1 minute": the dialog's default is minute-truncated
/// (`DateTime.now().add(Duration(minutes: 1))` -> hour/minute only), so a
/// Save that crosses a minute boundary can silently schedule the alarm 24
/// hours out - without this check, a caller's `pumpUntilFound
/// (ScreenAlarmActive)` would instead time out after 2 minutes with a
/// misleading "the alarm never rang" failure (docs/TODO.md T-23).
Future<void> createManualAlarmOneMinuteFromNow(
    WidgetTester tester, AppState appState) async {
  expect(find.byType(ScreenAlarms), findsOneWidget);

  // docs/TODO.md T-137: der Schirm oeffnet seit der Umstellung auf
  // "Scheduled"; der Add-Knopf gehoert zum Manual-Reiter (auf "Scheduled"
  // sitzt dort der Sync-Knopf). Ohne diesen Wechsel findet der Tipp unten
  // nichts - genau daran ist Lauf 34721191411 gescheitert.
  await tester.tap(find.text('Manual'));
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();

  final createdAlarm = appState.manualAlarms.single;
  final scheduledAlarms = await Alarm.getAlarms();
  AlarmSettings? nativeAlarm;
  for (final alarm in scheduledAlarms) {
    if (alarm.id == createdAlarm.id) {
      nativeAlarm = alarm;
      break;
    }
  }
  if (nativeAlarm == null) {
    fail('Alarm ${createdAlarm.id} was created in AppState but never reached '
        'the native alarm plugin (Alarm.getAlarms() has no matching entry).');
  }
  final difference = nativeAlarm.dateTime.difference(DateTime.now()).abs();
  if (difference > const Duration(minutes: 2)) {
    fail('Expected the created alarm to fire in ~1 minute, but it is '
        'scheduled for ${nativeAlarm.dateTime} (${difference.inMinutes} '
        'minutes from now) - likely the minute-truncated "now + 1 minute" '
        'dialog default landed on the wrong side of a minute boundary '
        '(docs/TODO.md T-23).');
  }
}


/// Nimmt Benachrichtigungen still entgegen. Ohne das wuerde jedes
/// Engine-Szenario echte Notifications auf dem Testgeraet erzeugen (und die
/// Bettzeit-Notification aus FR-16s Voraussetzung feuert bei jedem
/// Checkpoint).
class _SilentNotifications implements Notifications {
  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async =>
      id ?? 1;

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

/// Bringt die Engine mit **einem** injizierten Kalendertermin in einen exakt
/// vorhersagbaren Zustand und gibt dessen `hardFloor` (= den Terminbeginn)
/// zurueck.
///
/// Warum das deterministisch ist: mit `durationToWakeUp` und
/// `durationToGetReady` auf null ist der `hardFloor` genau der Terminbeginn
/// (FR-2), und ohne `preferredWakeUpTime` und ohne Vorgeschichte greift FR-10s
/// Kaltstart - der erste Tag mit echtem `hardFloor` bekommt **exakt** diesen
/// Wert, die Folgetage halten dieselbe Wanduhrzeit (FR-4 ohne Ziel). Aus einem
/// Termin entstehen so mehrere Alarme, was fuer die T-64-Pruefung sogar
/// gebraucht wird: es muss "die anderen Alarme" geben, die ein Dismiss nicht
/// loeschen darf.
///
/// `manualSync` als Auslöser ist wesentlich: FR-17s Tagessperre hat beim
/// App-Start schon zugeschlagen (main.dart fuhr einen appForeground-Checkpoint
/// gegen den leeren Geraetekalender), ein zweiter appForeground waere also ein
/// reines No-op. `manualSync` unterliegt der Sperre nicht und behandelt heute
/// nicht als abgeschlossen, das Fenster beginnt damit **heute**.
Future<DateTime> planOneCalendarEvent(
  AppState appState, {
  Duration leadTime = const Duration(hours: 2),
}) async {
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  appState.preferredWakeUpTime = null;

  // Ein echter Zukunftszeitpunkt ist Pflicht: AppState.addAlarm verwirft einen
  // ScheduledAlarm, dessen Zeit nicht nach dem ECHTEN DateTime.now() liegt -
  // nicht nach einem injizierten "now".
  final eventStart = DateTime.now().toUtc().add(leadTime);

  await runSchedulingCheckpoint(
    appState,
    trigger: CheckpointTrigger.manualSync,
    notifications: _SilentNotifications(),
    fetchEvents: (start, end) async => <Meeting>[
      Meeting(
        from: eventStart,
        to: eventStart.add(const Duration(hours: 1)),
        isAllDay: false,
        startTimeZone: 'Etc/UTC',
        endTimeZone: 'Etc/UTC',
      ),
    ],
  );

  return eventStart;
}

Set<DateTime> platformAlarmTimes(List<AlarmSettings> alarms) =>
    alarms.map((a) => a.dateTime).toSet();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Each scenario creates exactly one alarm; stopping everything before and
  // after every test keeps them independent regardless of how the previous
  // one ended, so one failure can't cascade into a false failure in the next
  // (docs/TODO.md T-23).
  setUp(() async {
    await Alarm.stopAll();
  });

  tearDown(() async {
    QrScanner.debugBarcodeStreamOverride = null;
    await Alarm.stopAll();
  });

  testWidgets(
    'manual alarm fires and is dismissed via the default overlay',
    (tester) async {
      final appState = await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester, appState);

      await pumpUntilFound(
        tester,
        find.byType(ScreenAlarmActive),
        timeout: const Duration(minutes: 2),
      );

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.byType(ScreenAlarmActive), findsNothing);
      expect(find.byType(ScreenAlarms), findsOneWidget);
      // Not just "the screen went away" - the alarm itself must actually
      // have stopped (docs/TODO.md T-09).
      expect(await Alarm.getAlarms(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'manual alarm with a deactivation code set is dismissed via QR scan',
    (tester) async {
      const testPayload = 'wakeywakey-e2e-test-code';

      final appState = await pumpFreshApp(tester);
      appState.deactivationCode = DeactivationCode(payload: testPayload);

      // A single-subscription controller, not Stream.value: QrScanner
      // subscribes to this in initState and _handleBarcode validates +
      // pops synchronously-ish on the very next event, so if the barcode
      // were queued up before QrScanner mounts (as Stream.value would),
      // the whole mount-validate-pop cycle can finish inside one
      // pumpUntilFound polling gap and never be observed as "found" at
      // all. Waiting to add the event until after QrScanner is confirmed
      // mounted removes that race entirely.
      final barcodeController = StreamController<BarcodeCapture>();
      QrScanner.debugBarcodeStreamOverride = barcodeController.stream;
      addTearDown(barcodeController.close);

      await createManualAlarmOneMinuteFromNow(tester, appState);

      await pumpUntilFound(
        tester,
        find.byType(QrScanner),
        timeout: const Duration(minutes: 2),
      );

      // T-08: the "guaranteed wake-up" gate's one job is refusing a wrong
      // code - a mismatching scan must never dismiss it.
      barcodeController.add(BarcodeCapture(barcodes: [
        Barcode(rawValue: 'not-the-right-code', format: BarcodeFormat.qrCode),
      ]));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(QrScanner), findsOneWidget);
      expect(await Alarm.getAlarms(), isNotEmpty);

      barcodeController.add(BarcodeCapture(barcodes: [
        Barcode(rawValue: testPayload, format: BarcodeFormat.qrCode),
      ]));

      // _handleBarcode validates the injected code and pops the scanner
      // automatically - just wait for it to close.
      await pumpUntilGone(
        tester,
        find.byType(QrScanner),
        timeout: const Duration(seconds: 15),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrScanner), findsNothing);
      expect(find.byType(ScreenAlarms), findsOneWidget);
      // Not just "the screen went away" - the alarm itself must actually
      // have stopped (docs/TODO.md T-09).
      expect(await Alarm.getAlarms(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'a created alarm survives being reloaded from on-device storage',
    (tester) async {
      final appState = await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester, appState);

      // Don't wait for it to ring - just confirm it's really on disk by
      // constructing a completely fresh AppState (as a real app restart
      // would) and checking it reads the alarm back via SharedPreferences,
      // rather than relying on in-memory state.
      final reloaded = AppState();
      await reloaded.initialized;

      expect(reloaded.manualAlarms, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  // ------------------------------------------------------------------------
  // scheduling-v2 auf dem Geraet (docs/TODO.md T-91).
  //
  // Warum das hier hingehoert und nicht in die Unit-Suite: KEIN Unit-Test
  // mockt den Kanal des `alarm`-Plugins. In `flutter test` wirft
  // `Alarm.set()`/`Alarm.getAlarms()` und wird geschluckt (apply_alarms.dart) -
  // die Unit-Suite prueft also ausschliesslich AppState-Listen. Alles zwischen
  // `appState.addAlarm` und einem wirklich registrierten Alarm war bis hier
  // unbelegt, und Phase 6 hat gerade den alten Motor geloescht.

  testWidgets(
      'T-63: an injected calendar event becomes real, registered alarms',
      (tester) async {
    final appState = await pumpFreshApp(tester);

    final eventStart = await planOneCalendarEvent(appState);

    // Der Plan ist in AppState angekommen ...
    expect(appState.scheduledAlarms, isNotEmpty,
        reason: 'FR-18 muss aus dem berechneten Plan echte ScheduledAlarms '
            'machen - genau das fehlte in T-63 vollstaendig.');
    // ... UND auf der Plattform. Das ist die Aussage, die kein Unit-Test
    // treffen kann.
    final onPlatform = await Alarm.getAlarms();
    for (final alarm in appState.scheduledAlarms) {
      expect(onPlatform.map((a) => a.id), contains(alarm.id),
          reason: 'ScheduledAlarm ${alarm.id} steht in AppState, aber nicht '
              'im Alarm-Plugin - genau die Divergenz aus T-74e.');
    }
    // Der Termintag selbst traegt exakt den hardFloor (FR-2 als Obergrenze,
    // hier mit Vorlaufzeiten von null also der Terminbeginn).
    expect(platformAlarmTimes(onPlatform), contains(alarmPlatformTime(eventStart)),
        reason: 'erwartet einen Alarm auf ${alarmPlatformTime(eventStart)}, '
            'bekommen ${platformAlarmTimes(onPlatform)}');
  });

  testWidgets(
      'T-61: the registered alarm carries the local reading of the planned instant',
      (tester) async {
    // Die Frame-Grenze, an der T-61 sass: ein Planwert ist ein UTC-getaggter
    // Instant, `AlarmSettings.dateTime` wird vom Plugin als lokale Wanduhrzeit
    // gelesen. Wurden die UTC-Ziffern einfach als lokal uebernommen, klingelte
    // der Alarm um den Geraeteversatz falsch.
    //
    // Diese Zusicherung hat nur Aussagekraft, wenn das Geraet NICHT auf UTC
    // steht - deshalb setzt .github/scripts/run_e2e_tests.sh die
    // Emulator-Zeitzone auf Europe/Berlin. Auf einem UTC-Geraet ist der Test
    // trivial wahr; die Zeitzone wird darum mitgemeldet.
    final appState = await pumpFreshApp(tester);

    final eventStart = await planOneCalendarEvent(appState);
    final expected = alarmPlatformTime(eventStart);
    final onPlatform = await Alarm.getAlarms();

    expect(
      platformAlarmTimes(onPlatform),
      contains(expected),
      reason: 'Geraetezone: ${DateTime.now().timeZoneName} '
          '(${DateTime.now().timeZoneOffset}). Der geplante Instant '
          '$eventStart entspricht lokal $expected; das Plugin hat '
          '${platformAlarmTimes(onPlatform)}. Weichen die um genau den '
          'Geraeteversatz ab, ist T-61 zurueck.',
    );
    // Und der Wert ist wirklich ein lokaler, kein UTC-getaggter.
    expect(expected.isUtc, isFalse);
  });

  testWidgets(
      'T-84: tone, volume and gentle wake reach the alarm plugin',
      (tester) async {
    final appState = await pumpFreshApp(tester);
    appState.selectedTone = 'assets/sounds/annoying_alarm.mp3';
    appState.selectedVolume = 0.35;
    appState.gentleWakeUpEnabled = true;

    await planOneCalendarEvent(appState);

    final onPlatform = await Alarm.getAlarms();
    final ids = appState.scheduledAlarms.map((a) => a.id).toSet();
    final ours = onPlatform.where((a) => ids.contains(a.id)).toList();
    expect(ours, isNotEmpty);
    for (final alarm in ours) {
      expect(alarm.assetAudioPath, 'assets/sounds/annoying_alarm.mp3');
      expect(alarm.volumeSettings.volume, closeTo(0.35, 0.001),
          reason: 'ScheduledAlarm hatte vor T-84 gar kein volume-Feld - alle '
              'geplanten Alarme klangen mit dem Default 0.6 und ignorierten '
              'appState.selectedVolume, obwohl es dafuer eine UI gibt.');
    }
  });

  testWidgets(
      'T-64: dismissing a ringing alarm leaves the planned week registered',
      (tester) async {
    // Der schwerste Befund des Konsistenz-Durchgangs, hier auf dem Geraet:
    // `onAlarmHandled` rief den alten Scheduler, der zuerst ALLE
    // ScheduledAlarms loeschte und dann ohne Ersatz abbrach, weil
    // `appState.meetings` leer war. Nach einem Dismiss stand der Nutzer ohne
    // jeden Alarm da.
    final appState = await pumpFreshApp(tester);
    await planOneCalendarEvent(appState);

    final plannedIds = appState.scheduledAlarms.map((a) => a.id).toSet();
    expect(plannedIds, isNotEmpty);

    // Ein manueller Alarm klingelt und wird ueber das Overlay abgeschaltet -
    // derselbe Pfad, der `Handler.onAlarmHandled` aufruft.
    await createManualAlarmOneMinuteFromNow(tester, appState);
    await pumpUntilFound(tester, find.byType(ScreenAlarmActive));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await pumpUntilGone(tester, find.byType(ScreenAlarmActive));

    // Die geplanten Alarme muessen samt und sonders noch da sein - in
    // AppState UND auf der Plattform.
    expect(appState.scheduledAlarms.map((a) => a.id).toSet(), plannedIds,
        reason: 'ein Dismiss darf die geplante Woche nicht antasten (T-64)');
    final stillOnPlatform = (await Alarm.getAlarms()).map((a) => a.id).toSet();
    for (final id in plannedIds) {
      expect(stillOnPlatform, contains(id),
          reason: 'ScheduledAlarm $id ist nach dem Dismiss von der Plattform '
              'verschwunden - genau der Ausgang, den T-64 beschreibt.');
    }
  });
}
