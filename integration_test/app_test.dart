// Real end-to-end tests, driven against a real (emulated or physical)
// Android device via `flutter test integration_test/` (or `flutter drive`).
// These exercise the actual native `alarm` plugin - alarms really fire via
// the OS. Scenario 3's persistence check does a genuine storage round-trip
// since docs/TODO.md T-04: it resets the memoised SharedPreferences instance
// and reloads from the platform before re-reading. It used to read back an
// in-process cache and would have stayed green with storage entirely broken.
// What it still does NOT cover is survival across a real process death or
// reboot - that is measured outside the suite by
// `scripts/verify-alarm-survival.sh` against a physical phone (T-93).
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
// QrScanner.debugScanStreamOverride rather than actually feeding camera
// data - see that field's doc comment in lib/screens/scan_code/qr_scanner.dart
// and docs/TODO.md T-16 for why, and what that does and doesn't prove.

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/main.dart';
import 'package:crescendo_alarm/models/scheduling/checkpoint.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/screens/alarms/screen_active_alarm.dart';
import 'package:crescendo_alarm/screens/alarms/screen_alarms.dart';
import 'package:crescendo_alarm/models/scan_code/scan_result.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/utils.dart';

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

  // docs/TODO.md T-41: cleared prefs means the privacy policy is the first
  // screen shown now, before anything is requested - this suite predates
  // that change and used to go straight to the permission check. Not
  // pumpAndSettle (see test/widget_test.dart's own comment): the splash
  // screen's rotation AnimationController repeats forever while it's
  // mounted, so "no more frames scheduled" never becomes true here.
  await tester.pump();
  await tester.pump();
  final continueButton = find.text('Continue');
  if (continueButton.evaluate().isNotEmpty) {
    await tester.tap(continueButton);
    await tester.pump();
  }

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

  // docs/TODO.md T-137: since the switch, the screen opens on "Scheduled";
  // the Add button belongs to the Manual tab (on "Scheduled" the Sync
  // button sits there instead). Without this tab switch, the tap below
  // finds nothing - exactly what run 34721191411 failed on.
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


/// Silently swallows notifications. Without this, every engine scenario
/// would produce real notifications on the test device (and the bedtime
/// notification from FR-16's precondition fires on every checkpoint).
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

/// Brings the engine into an exactly predictable state with **one** injected
/// calendar appointment, and returns its `hardFloor` (= the appointment
/// start).
///
/// Why this is deterministic: with `durationToWakeUp` and
/// `durationToGetReady` at null, `hardFloor` is exactly the appointment start
/// (FR-2), and without `preferredWakeUpTime` and with no history, FR-10's
/// cold start applies - the first day with a real `hardFloor` gets **exactly**
/// this value, and the following days hold the same wall-clock time (FR-4
/// with no target). One appointment thus produces several alarms, which is
/// even needed for the T-64 check: there must be "the other alarms" that a
/// dismiss must not delete.
///
/// `manualSync` as the trigger is essential: FR-17's daily lock has already
/// kicked in at app start (main.dart ran an appForeground checkpoint against
/// the empty device calendar), so a second appForeground would be a pure
/// no-op. `manualSync` is not subject to the lock and does not treat today as
/// concluded, so the window begins **today**.
Future<DateTime> planOneCalendarEvent(
  AppState appState, {
  Duration leadTime = const Duration(hours: 2),
}) async {
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  appState.preferredWakeUpTime = null;

  // A real future instant is mandatory: AppState.addAlarm rejects a
  // ScheduledAlarm whose time is not after the REAL DateTime.now() - not
  // after an injected "now".
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
    QrScanner.debugScanStreamOverride = null;
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
      // have stopped (docs/TODO.md T-09). Not `isEmpty`: the "add alarm"
      // dialog defaults `repeatOnDays` to today (docs/TODO.md T-14), so
      // `Handler.onAlarmHandled` legitimately re-arms it for next week on
      // dismiss - a real, intended re-arm for the FUTURE is fine; an entry
      // stuck at (or before) the time that just rang is not.
      expect((await Alarm.getAlarms()).every((a) => a.dateTime.isAfter(DateTime.now())),
          isTrue,
          reason: 'no alarm may remain armed at or before the time it just '
              'rang - a repeat re-arm for a future occurrence is fine');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'manual alarm with a deactivation code set is dismissed via QR scan',
    (tester) async {
      const testPayload = 'crescendo-alarm-e2e-test-code';

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
      final barcodeController = StreamController<ScanResult>();
      QrScanner.debugScanStreamOverride = barcodeController.stream;
      addTearDown(barcodeController.close);

      await createManualAlarmOneMinuteFromNow(tester, appState);

      await pumpUntilFound(
        tester,
        find.byType(QrScanner),
        timeout: const Duration(minutes: 2),
      );

      // T-08: the "guaranteed wake-up" gate's one job is refusing a wrong
      // code - a mismatching scan must never dismiss it.
      barcodeController.add(const ScanResult('not-the-right-code'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(QrScanner), findsOneWidget);
      expect(await Alarm.getAlarms(), isNotEmpty);

      barcodeController.add(ScanResult(testPayload));

      // _handleScan validates the injected code and pops the scanner
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
      // have stopped (docs/TODO.md T-09). Not `isEmpty` - see the same-shaped
      // assertion in the default-overlay scenario above for why.
      expect((await Alarm.getAlarms()).every((a) => a.dateTime.isAfter(DateTime.now())),
          isTrue,
          reason: 'no alarm may remain armed at or before the time it just '
              'rang - a repeat re-arm for a future occurrence is fine');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'a created alarm survives being reloaded from on-device storage',
    (tester) async {
      final appState = await pumpFreshApp(tester);
      await createManualAlarmOneMinuteFromNow(tester, appState);
      final created = appState.manualAlarms.single;

      // docs/TODO.md T-04: this test used to prove nothing. Building a fresh
      // `AppState` does NOT re-read storage - `SharedPreferences.getInstance()`
      // memoises its instance behind a static `Completer` and answers every
      // read from an in-process cache, so the "restart" read back exactly the
      // object graph the test had just written in memory. It would have stayed
      // green with storage entirely broken.
      //
      // Two steps are needed to make it a real round-trip, and both matter:
      // `resetStatic()` drops the memoised instance, and `reload()` makes the
      // next instance fetch its values from the platform instead of the cache.
      SharedPreferences.resetStatic();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final reloaded = AppState();
      await reloaded.initialized;

      // And not just "some alarm came back": id and time, because a wrong id
      // is exactly what a broken round-trip produces - the list looks right
      // and no longer matches the alarm the platform has armed.
      expect(reloaded.manualAlarms, hasLength(1));
      expect(reloaded.manualAlarms.single.id, created.id);
      expect(reloaded.manualAlarms.single.time, created.time);

      // The other half of the durability question (R3): the alarm the OS holds
      // must still be there too, and carry the same id.
      final platformIds = (await Alarm.getAlarms()).map((a) => a.id).toSet();
      expect(platformIds, contains(created.id),
          reason: 'the app remembers the alarm, but AlarmManager is what makes '
              'it ring');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  // ------------------------------------------------------------------------
  // scheduling-v2 on the device (docs/TODO.md T-91).
  //
  // Why this belongs here and not in the unit suite: NO unit test mocks the
  // `alarm` plugin's channel. In `flutter test`, `Alarm.set()`/
  // `Alarm.getAlarms()` throws and is swallowed (apply_alarms.dart) - so the
  // unit suite only ever checks AppState lists. Everything between
  // `appState.addAlarm` and an actually registered alarm was unproven up to
  // this point, and Phase 6 has just deleted the old engine.

  testWidgets(
      'T-63: an injected calendar event becomes real, registered alarms',
      (tester) async {
    final appState = await pumpFreshApp(tester);

    final eventStart = await planOneCalendarEvent(appState);

    // The plan has arrived in AppState ...
    expect(appState.scheduledAlarms, isNotEmpty,
        reason: 'FR-18 must turn the computed plan into real ScheduledAlarms '
            '- that is exactly what T-63 was missing entirely.');
    // ... AND on the platform. That's the assertion no unit test can make.
    final onPlatform = await Alarm.getAlarms();
    for (final alarm in appState.scheduledAlarms) {
      expect(onPlatform.map((a) => a.id), contains(alarm.id),
          reason: 'ScheduledAlarm ${alarm.id} is in AppState, but not in the '
              'alarm plugin - exactly the divergence from T-74e.');
    }
    // The appointment day itself carries exactly the hardFloor (FR-2 as an
    // upper bound, here with lead times of zero, so the appointment start).
    expect(platformAlarmTimes(onPlatform), contains(alarmPlatformTime(eventStart)),
        reason: 'expected an alarm at ${alarmPlatformTime(eventStart)}, '
            'got ${platformAlarmTimes(onPlatform)}');
  });

  testWidgets(
      'T-61: the registered alarm carries the local reading of the planned instant',
      (tester) async {
    // The frame boundary T-61 sat on: a planned value is a UTC-tagged
    // instant, `AlarmSettings.dateTime` is read by the plugin as a local
    // wall-clock time. If the UTC digits were simply carried over as local,
    // the alarm rang off by the device offset.
    //
    // This assertion only has any power if the device is NOT on UTC -
    // that's why .github/scripts/run_e2e_tests.sh sets the emulator's time
    // zone to Europe/Berlin. On a UTC device the test is trivially true; the
    // time zone is therefore reported alongside.
    final appState = await pumpFreshApp(tester);

    final eventStart = await planOneCalendarEvent(appState);
    final expected = alarmPlatformTime(eventStart);
    final onPlatform = await Alarm.getAlarms();

    expect(
      platformAlarmTimes(onPlatform),
      contains(expected),
      reason: 'Device zone: ${DateTime.now().timeZoneName} '
          '(${DateTime.now().timeZoneOffset}). The planned instant '
          '$eventStart corresponds locally to $expected; the plugin has '
          '${platformAlarmTimes(onPlatform)}. If these differ by exactly '
          'the device offset, T-61 is back.',
    );
    // And the value really is a local one, not UTC-tagged.
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
          reason: 'ScheduledAlarm had no volume field at all before T-84 - '
              'every planned alarm rang with the default 0.6 and ignored '
              'appState.selectedVolume, even though there is a UI for it.');
    }
  });

  testWidgets(
      'T-64: dismissing a ringing alarm leaves the planned week registered',
      (tester) async {
    // The most severe finding of the consistency pass, here on the device:
    // `onAlarmHandled` called the old Scheduler, which first deleted ALL
    // ScheduledAlarms and then aborted with no replacement, because
    // `appState.meetings` was empty. After a dismiss, the user was left
    // without a single alarm.
    final appState = await pumpFreshApp(tester);
    await planOneCalendarEvent(appState);

    final plannedIds = appState.scheduledAlarms.map((a) => a.id).toSet();
    expect(plannedIds, isNotEmpty);

    // A manual alarm rings and is switched off via the overlay - the same
    // path that calls `Handler.onAlarmHandled`.
    await createManualAlarmOneMinuteFromNow(tester, appState);
    await pumpUntilFound(tester, find.byType(ScreenAlarmActive));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await pumpUntilGone(tester, find.byType(ScreenAlarmActive));

    // The planned alarms must all still be there, without exception - in
    // AppState AND on the platform.
    expect(appState.scheduledAlarms.map((a) => a.id).toSet(), plannedIds,
        reason: 'a dismiss must not touch the planned week (T-64)');
    final stillOnPlatform = (await Alarm.getAlarms()).map((a) => a.id).toSet();
    for (final id in plannedIds) {
      expect(stillOnPlatform, contains(id),
          reason: 'ScheduledAlarm $id disappeared from the platform after '
              'the dismiss - exactly the outcome T-64 describes.');
    }
  });
}
