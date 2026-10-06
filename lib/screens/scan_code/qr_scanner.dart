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

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:provider/provider.dart';
import 'package:crescendo_alarm/screens/alarms/snooze_button.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/ringing_watch.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_stop.dart';
import 'package:crescendo_alarm/models/scan_code/scan_result.dart';
import 'package:crescendo_alarm/utils/permissions.dart';
import 'package:crescendo_alarm/utils/ring_notification.dart';

/// Pure comparison at the heart of the "guaranteed wake-up" gate: does the
/// scanned payload match the stored deactivation code? Extracted out of
/// [_QrScannerState] so it's unit-testable without a device - see
/// test/qr_scanner_validation_test.dart.
///
/// When [storedCode] is null there is nothing to validate against; this
/// fails open (returns true) to match the app's existing "illegal state"
/// behavior, which prioritizes not locking a user in behind a scanner over
/// enforcing a code that was never actually set.
bool isDeactivationCodeValid(
    DeactivationCode? storedCode, String? scannedPayload) {
  if (storedCode == null) {
    return true;
  }
  return storedCode.payload == scannedPayload;
}

/// The camera screen behind the "guaranteed wake-up" gate, in two flows:
/// importing a deactivation code (`PageImportQr`, with no code stored yet -
/// the first decoded code becomes it) and deactivating the ringing alarm
/// [alarmId] (shown by `Handler.handleAlarm` when a code is required - only
/// a scan matching the stored code stops it).
///
/// Back navigation is blocked (`PopScope(canPop: false)`). The ways out are
/// a valid scan, Snooze (FR-20), [RingingWatch] seeing the alarm stopped
/// elsewhere, the import flow's Cancel button, and the emergency stop once
/// scanning shows no sign of working.
class QrScanner extends StatefulWidget {
  /// Shows a Cancel button. Only the code-import flow sets it: on the ringing
  /// gate, leaving without a valid scan must not be possible.
  final bool displayExitButton;

  /// docs/TODO.md T-74e: the id of the alarm that is actually ringing. Without
  /// it this screen had to `Alarm.stop` **every** saved alarm to silence the
  /// ringing one, which cancelled unrelated future alarms at the platform
  /// level while leaving `AppState`'s lists untouched - a divergence FR-18's
  /// sync could not see (it models "existing" from `AppState`). `null` (the
  /// import flow) still stops every platform alarm, but only while something
  /// is actually ringing - see `deactivationStopTargets`.
  final int? alarmId;

  const QrScanner({
    super.key,
    this.displayExitButton = false,
    this.alarmId,
  });

  /// Test-only seam: when set, this stream replaces the camera for every
  /// `QrScanner` instance, and the live preview is not built at all.
  ///
  /// A static field, not a constructor parameter, because production code
  /// (`Handler.handleAlarm`) constructs `QrScanner()` directly with nowhere to
  /// thread a parameter through. Tests set it before triggering the ringing
  /// flow and exercise the deactivation logic without a camera feed - no
  /// scanner plugin's native preview can be driven from a test.
  ///
  /// It carries the app's own [ScanResult] since docs/TODO.md T-33, so the
  /// seam no longer names a scanner package's type.
  ///
  /// docs/TODO.md T-16 records the cost of this seam honestly: it exists in
  /// release builds too. What it buys, beyond the E2E scenarios, is the
  /// negative test the gate had never had (test/qr_scanner_gate_test.dart) -
  /// a wrong code must not open it.
  @visibleForTesting
  static Stream<ScanResult>? debugScanStreamOverride;

  /// Test-only seam: when set, [RingingWatch] observes this stream instead
  /// of the real `Alarm.ringing` - which has no platform channel in
  /// `flutter test` and never carries a test's fake alarm id.
  @visibleForTesting
  static Stream<AlarmSet>? debugRingingStreamOverride;

  /// Test-only seam (docs/TODO.md T-215): the camera (re)initialisation
  /// results `ReaderWidget.onControllerCreated` reports - `null` for success,
  /// the error otherwise - delivered to the same handler. `ReaderWidget` is
  /// not built while [debugScanStreamOverride] is set, so without this a
  /// test could not reproduce "the camera came back after a resume". Like
  /// the seams above it exists in release builds too (docs/TODO.md T-16),
  /// and is `null` there.
  @visibleForTesting
  static Stream<Object?>? debugCameraInitStreamOverride;

  /// Test-only seam: the real `Handler.onAlarmHandled` has no way of its own
  /// to observe how many times it was called - needed to pin down the
  /// double-dismiss bug `_handleAlarmOnce` guards against (see
  /// `screen_active_alarm.dart`'s identical seam and doc comment for the
  /// full story - the same `Alarm.stop()`-updates-`Alarm.ringing` race
  /// applies here between a successful QR validation and `RingingWatch`).
  @visibleForTesting
  static void Function(AppState appState, int alarmId)?
      debugOnAlarmHandledOverride;

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> {
  StreamSubscription<Object?>? _subscription;
  StreamSubscription<Object?>? _cameraInitSubscription;
  late final AppState _appState;

  /// Set when the scanner may not be working: the camera reported an error,
  /// no frame reached the decoder within [_proofOfLifeTimeout], or no valid
  /// code was found within [_maxTimeWithoutValidScan]. It drives the
  /// emergency stop below - without it a "guaranteed wake-up" alarm whose
  /// scanner never comes up leaves the user on a `PopScope(canPop: false)`
  /// screen with no scanner and no way out.
  ///
  /// docs/TODO.md T-215: **never cleared** once set. It used to follow every
  /// `onControllerCreated` (`error != null`), and ReaderWidget calls that
  /// again after every resume and camera toggle - a successful
  /// re-initialisation withdrew the offer, and the timers that had raised it
  /// fire only once. A camera that initialises is not a camera that can see.
  /// Maintainer (2026-10-06): "Der soll nicht verschwinden, aber wegwischbar
  /// sein." - only the user hides it, see [_emergencyStopSwipedAway].
  bool _emergencyStopOffered = false;

  /// docs/TODO.md T-215: the user swiped the offer away ("let me try
  /// scanning again"). Cleared - the offer shown again - by the next failure
  /// condition: a camera error, or [_maxTimeWithoutValidScan] more without a
  /// valid code ([_startMaxScanDurationTimer] re-arms on the swipe). So the
  /// escape hatch is hidden only by the user's own action, and never for the
  /// rest of the ring: a swipe by mistake costs at most one more timeout.
  bool _emergencyStopSwipedAway = false;

  /// Gives each appearance its own `Dismissible` key - a dismissed
  /// `Dismissible` must not come back under the same key.
  int _emergencyStopAppearance = 0;

  bool get _showEmergencyStop =>
      _emergencyStopOffered && !_emergencyStopSwipedAway;

  /// Evidence that the decode loop is alive: a scan arrived, successful or not.
  bool _scannerProvedAlive = false;

  /// The escape hatch's main trigger.
  ///
  /// An independent review listed six ways the camera can end up dead without
  /// `onControllerCreated` ever reporting an error - an empty camera list, a
  /// throwing image stream (which reports success first), a controller
  /// replaced mid-init, a re-entrant init hitting the library's own guard, a
  /// decode isolate that failed to start, and an unscannable frame format.
  /// Several of those are likeliest exactly when this screen appears: while
  /// the device is waking from the lock screen.
  ///
  /// So the button is not driven by an initialisation event alone but by the
  /// absence of evidence that scanning works. If nothing has been decoded
  /// after this long, the user gets a way out regardless of what any callback
  /// did or did not report.
  static const Duration _proofOfLifeTimeout = Duration(seconds: 10);
  Timer? _proofOfLifeTimer;

  /// A second, longer-running timeout, independent of [_scannerProvedAlive].
  ///
  /// Real-device report (docs/TODO.md T-38): a hardware camera kill-switch
  /// (some devices have one) can leave the camera "running" in every sense
  /// [_proofOfLifeTimer] can observe - frames keep arriving, decode attempts
  /// keep running, `onScanFailure` fires normally for each one - while the
  /// feed itself is permanently black/blank and can never produce a valid
  /// decode. That is indistinguishable, from this screen's side, from "the
  /// user just hasn't held the code up yet" - so proof-of-life alone can
  /// leave the escape hatch withheld forever from someone whose camera is
  /// physically blocked. This offers it anyway once scanning has been
  /// running for a long time with no VALID code ever found, regardless of
  /// whether individual scan attempts kept "succeeding" at producing a
  /// (wrong or empty) result.
  static const Duration _maxTimeWithoutValidScan = Duration(seconds: 30);
  Timer? _maxScanDurationTimer;

  /// Only set when this screen was opened for a specific ringing alarm
  /// (`widget.alarmId != null`) - a plain code-import/scan has nothing
  /// ringing to watch. See RingingWatch's doc comment for the bug this
  /// guards against: the alarm being stopped somewhere other than this
  /// screen, which it otherwise never learns about. Since
  /// `androidStopAlarmOnDismiss: false` (`ringing_alarm_settings.dart`) that
  /// is no longer a notification swipe, but e.g. `Alarm.stopAll()` from
  /// `Handler.handleAlarm`'s "no screen could be shown" fallback.
  RingingWatch? _ringingWatch;

  /// docs/TODO.md T-229: only for a ringing alarm, like [_ringingWatch].
  RingNotificationQuieter? _notificationQuieter;

  /// Guards `widget.alarmId` specifically against a double
  /// `Handler.onAlarmHandled` call - see `_handleAlarmOnce`.
  bool _ringingAlarmHandled = false;

  /// Set synchronously the instant Snooze is pressed - see
  /// `SnoozeButton.onBeforeSnooze`'s doc comment and
  /// `screen_active_alarm.dart`'s identical field for why "before", not
  /// "after a successful postponement".
  bool _snoozing = false;

  @override
  void initState() {
    debugPrint("=====initState: Creating new QRScannerState");
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);

    // Maintainer request (2026-09-20): camera access is requested here,
    // lazily, rather than upfront on the splash screen - this is the one
    // screen that shares both flows that ever need it (the initial
    // code-import screen and the alarm-deactivation gate).
    unawaited(requestCameraPermission());

    if (widget.alarmId case final int ringingId) {
      _ringingWatch = RingingWatch(
        alarmId: ringingId,
        ringingStream: QrScanner.debugRingingStreamOverride,
        onGone: () {
          if (!mounted) return;
          if (!_snoozing) _handleAlarmOnce(ringingId);
          _closeView();
        },
      );
      _notificationQuieter = RingNotificationQuieter(ringingId);
    }

    // No lifecycle observer any more: ReaderWidget starts and stops its own
    // camera with the app lifecycle. The previous scanner needed one, and its
    // handler was the mechanism behind half of docs/TODO.md T-16 - an
    // `inactive` -> `resumed` pair cancelled the injected test stream and
    // re-listened to the camera instead.
    //
    // The camera is driven by ReaderWidget in build(); only the injected test
    // stream needs a subscription here.
    _subscription = QrScanner.debugScanStreamOverride?.listen(_handleScan);
    _cameraInitSubscription =
        QrScanner.debugCameraInitStreamOverride?.listen(_onCameraInitialised);

    _proofOfLifeTimer = Timer(_proofOfLifeTimeout, () {
      if (!mounted || _scannerProvedAlive) return;
      debugPrint(
          '=====qrScanner: no scan within ${_proofOfLifeTimeout.inSeconds}s '
          '- offering the emergency stop');
      _offerEmergencyStop();
    });

    _startMaxScanDurationTimer();
  }

  /// Deliberately not cancelled by _noteScannerAlive() - see
  /// [_maxScanDurationTimer]'s own doc comment for why "the scanner is
  /// running" is not the same question as "the camera can actually see
  /// anything". Started with the screen, and again when the user swipes the
  /// emergency stop away (docs/TODO.md T-215).
  void _startMaxScanDurationTimer() {
    _maxScanDurationTimer?.cancel();
    _maxScanDurationTimer = Timer(_maxTimeWithoutValidScan, () {
      if (!mounted) return;
      debugPrint(
          '=====qrScanner: no valid code within ${_maxTimeWithoutValidScan.inSeconds}s '
          '- offering the emergency stop regardless of scanner activity');
      _offerEmergencyStop();
    });
  }

  /// A failure condition occurred: show the emergency stop, also if the user
  /// had swiped an earlier offer away.
  void _offerEmergencyStop() {
    setState(() {
      if (!_emergencyStopOffered || _emergencyStopSwipedAway) {
        _emergencyStopAppearance++;
      }
      _emergencyStopOffered = true;
      _emergencyStopSwipedAway = false;
    });
  }

  void _onEmergencyStopSwipedAway() {
    setState(() => _emergencyStopSwipedAway = true);
    _startMaxScanDurationTimer();
  }

  @override
  void dispose() {
    _proofOfLifeTimer?.cancel();
    _maxScanDurationTimer?.cancel();
    _ringingWatch?.cancel();
    _notificationQuieter?.dispose();

    // Stop listening to the injected events, if any. ReaderWidget disposes of
    // its own camera controller.
    unawaited(_subscription?.cancel());
    unawaited(_cameraInitSubscription?.cancel());

    super.dispose();
  }

  /// ReaderWidget's `onControllerCreated`, after the first start and again
  /// after every resume and camera toggle. Only an error counts: a success
  /// does not withdraw an offer already made (docs/TODO.md T-215).
  void _onCameraInitialised(Object? error) {
    if (!mounted || error == null) return;
    debugPrint('=====qrScanner: camera unavailable: ${error.runtimeType}');
    _offerEmergencyStop();
  }

  /// Any frame that reached the decoder - hit or miss - proves the loop runs.
  void _noteScannerAlive() {
    _scannerProvedAlive = true;
    _proofOfLifeTimer?.cancel();
  }

  Future<void> _handleScan(ScanResult scan) async {
    _noteScannerAlive();
    if (mounted) {
      // A decode with no usable text must never become a stored code: an
      // empty payload would leave a gate nobody can ever open again. `null`
      // comes from the test seam; `''` a decoder can genuinely produce.
      final payload = scan.payload;
      if (payload == null || payload.isEmpty) {
        return;
      }

      if (_appState.deactivationCode == null) {
        // docs/TODO.md T-89: the payload IS the deactivation secret - anyone
        // holding this log line could defeat the "guaranteed" wake-up at will.
        // Only the fact of an import is logged, never the value.
        debugPrint('=====qrScanner: Imported a deactivation code');
        Diag.qrGate(outcome: QrOutcome.imported, codeWasSet: false);
        final newDeactivationCode = DeactivationCode(payload: payload);
        setState(() {
          _appState.deactivationCode = newDeactivationCode;
        });

        // Close immediately. Leaving the camera running meant the SAME code
        // decoded again a second later - and that second decode took the
        // validation branch, which with no `alarmId` used to cancel every
        // armed alarm. This branch is only reachable from the import screen
        // (a ringing alarm opens the scanner only when a code is already set),
        // so there is nothing else for it to do here.
        _closeView();
      }
      else {
        bool validationSuccessful = false;
        try {
          validationSuccessful = await _validateDeactivationCode(scan);
        } catch (e) {
          debugPrint(
              '=====handleScan: Error validating Deactivation Code: ${e.runtimeType}');
        }
        if (validationSuccessful) {
          _closeView();
        }
      }
    } // end of 'if mounted'
  }

  Future<bool> _validateDeactivationCode(ScanResult scan) async {
    // Validate the scanned code BEFORE stopping any alarms, so a wrong or
    // arbitrary QR code can never silently disarm the alarm.
    if (!isDeactivationCodeValid(_appState.deactivationCode, scan.payload)) {
      return false;
    }

    if (_appState.deactivationCode == null) {
      // Not reachable from _handleScan, which validates only while a code is
      // stored - kept as a fail-open: isDeactivationCodeValid already
      // returned true above so the user is never locked in behind the
      // scanner.
      debugPrint('=====qrValidator: ILLEGAL STATE!!!');
      return true;
    }

    // docs/TODO.md T-89: only the outcome, never the value. This line fires
    // exactly when the user switches off the alarm in the morning - so
    // reliably every day.
    debugPrint('=====qrValidator: scanned code VALIDATED');
    // No parameter for the payload - none for its length or a hash either,
    // both would be a way back to the secret.
    Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);

    try {
      final idsToStop = deactivationStopTargets(
        ringingAlarmId: widget.alarmId,
        platformAlarmIds: widget.alarmId == null
            ? (await Alarm.getAlarms()).map((a) => a.id).toList()
            : const <int>[],
        anythingRinging: widget.alarmId != null || await Alarm.isRinging(),
      );
      for (final id in idsToStop) {
        try {
          await Alarm.stop(id);
          _handleAlarmOnce(id);
        } catch (e) {
          debugPrint(
              "=====ScreenAlarmActiveState: Failed to stop alarm: ${e.runtimeType}");
        }
      }
    } catch (e) {
      debugPrint(
          '=====validateDeactivationCode: Error stopping alarms: ${e.runtimeType}');
    }

    // Only close the scanner if nothing is still ringing - a stop failure
    // above (an exception, or a native stop that silently returns false)
    // must never look identical to success from here.
    final bool stillRinging = await Alarm.isRinging();
    if (stillRinging) {
      debugPrint(
          '=====validateDeactivationCode: An alarm is still ringing after stop attempts!');
    }
    return !stillRinging;
  }

  @override
  Widget build(BuildContext context) {
    final exitButton = ElevatedButton.icon(
      onPressed: _closeView,
      label: Text(
        'Cancel',
        style: TextStyle(color: _appState.accentColor),
      ),
      icon: Icon(Icons.close, color: _appState.accentColor),
    );

    // Shown instead of the (hidden-by-design) exit button once
    // _emergencyStopOffered is set (and not swiped away) - a camera error (permission revoked, hardware busy, unsupported
    // device, ...) or one of the two timeouts (which also catch a hardware
    // camera kill-switch): without this, a "guaranteed wake-up" alarm whose
    // QR scanner can never work would leave the user stuck on a
    // PopScope(canPop: false) screen with no scanner and no way out.
    //
    // User request: named for what actually triggers it (the camera, not
    // some generic "give up" state) and sized up - this is the one control
    // standing between someone and an alarm they otherwise cannot stop, so
    // it should read and hit like it.
    final emergencyStopButton = ElevatedButton.icon(
      onPressed: _emergencyStopAndClose,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      label: Text(
        'Camera not working - Stop alarm',
        style: TextStyle(color: _appState.accentColor),
      ),
      icon: Icon(Icons.videocam_off, size: 28, color: _appState.accentColor),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // FR-20: snooze NEVER needs the code. The scan switches off;
            // snooze only postpones - within a budget that cannot endanger
            // the appointment. Requiring a scan just to keep being woken up
            // would be pointless, and would risk pushing the user to switch
            // the device off entirely.
            // `alarmId` is nullable here: the screen is also opened for
            // plain code scanning, with nothing ringing. Then there is
            // nothing to postpone.
            if (widget.alarmId case final int ringingId)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SnoozeButton(
                    alarmId: ringingId,
                    onBeforeSnooze: () => _snoozing = true,
                    onSnoozeAttemptFailed: () => _snoozing = false,
                    onSnoozed: _closeView,
                  ),
                ),
              ),
            // The live preview. Not built at all when a test stream is
            // injected: no scanner plugin's camera can run in a widget test,
            // and building it would be the only thing standing between the
            // gate and a unit test of it.
            if (QrScanner.debugScanStreamOverride == null)
              Center(
                child: ReaderWidget(
                  // docs/REQUIREMENTS.md R13: "any pre-existing code already
                  // at hand" is not only QR - a barcode on a household
                  // object is just as realistic a candidate for a
                  // deactivation code. `Format.any` is every 1D/2D symbology
                  // zxing-cpp can decode (linear barcodes - EAN/UPC/Code128/
                  // Codabar/ITF/GS1 DataBar - plus every 2D format besides
                  // QR: Aztec, Data Matrix, PDF417, MaxiCode, Micro/
                  // rectangular Micro QR). `DeactivationCode`'s payload is a
                  // plain string either way, so nothing downstream of a scan
                  // needs to know or care which symbology produced it.
                  codeFormat: Format.any,
                  // docs/TODO.md T-44: the gallery button is off, deliberately.
                  // Decoding a QR code from a stored image would let a user
                  // photograph the code once and defeat the "guaranteed
                  // wake-up" gate from bed. The camera is the point.
                  showGallery: false,
                  showFlashlight: true,
                  showToggleCamera: true,
                  // Real-device report: most pre-existing QR codes (R13 -
                  // anything already at hand, not only a code this app itself
                  // rendered) were not recognized at all. ReaderWidget only
                  // decodes within a centre crop, and its own default there
                  // (`cropPercent: 0.5`) is just 50% of the shorter camera
                  // dimension - a code that isn't small and perfectly
                  // centred in that box, which is normal for one printed on
                  // an arbitrary real-world object rather than shown
                  // close-up on a second device's screen, never reaches the
                  // decoder at all. Widened to 85%. `tryHarder`/`tryInverted`
                  // are additional zxing-cpp decode passes for exactly the
                  // conditions a code "already at hand" is likely to have
                  // (an angle, a curved surface, light-on-dark colouring)
                  // that this app's own generated codes never do - off by
                  // default because they cost time, which R13 makes worth
                  // spending here.
                  cropPercent: 0.85,
                  tryHarder: true,
                  tryInverted: true,
                  // Real-device report (2026-09-19): recognition works but is
                  // slow/inconsistent. `scanDelay` (default 1000ms) is the
                  // artificial pause `ReaderWidget` inserts between decode
                  // attempts whenever a frame comes back empty - so scanning
                  // only tried roughly once a second, where mobile_scanner
                  // (T-16, before the T-33 licence-driven swap) decoded at
                  // frame rate. Shortened to close that gap: every extra
                  // attempt per second is another chance to catch a
                  // well-aligned, in-focus frame, which is exactly what
                  // "slow AND unreliable" together point at - not only a
                  // speed complaint.
                  scanDelay: const Duration(milliseconds: 150),
                  scanDelaySuccess: const Duration(milliseconds: 500),
                  onScan: (code) => _handleScan(ScanResult(code.text)),
                  // A failed decode is still proof that frames are arriving
                  // and being looked at - it keeps the escape hatch closed and
                  // distinguishes "I see nothing" from "that is the wrong
                  // code", which the app could not tell apart before.
                  onScanFailure: (_) => _noteScannerAlive(),
                  loading: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Starting the camera...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                  onControllerCreated: (controller, error) =>
                      _onCameraInitialised(error),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.displayExitButton)
                      exitButton
                    else if (_showEmergencyStop)
                      // docs/TODO.md T-215: stays until the user swipes it
                      // away - see _emergencyStopSwipedAway.
                      Dismissible(
                        key: ValueKey<int>(_emergencyStopAppearance),
                        onDismissed: (_) => _onEmergencyStopSwipedAway(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            emergencyStopButton,
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Swipe aside to hide',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `Alarm.stop(id)` (in the validation loop below) updates `Alarm.ringing`
  /// as part of that same call, which `RingingWatch` also observes - so a
  /// successful validation and `RingingWatch.onGone` could both call
  /// `Handler.onAlarmHandled` for `widget.alarmId` (the one id `RingingWatch`
  /// watches). Harmless before T-14 started re-arming a repeating
  /// `ManualAlarm` from `onAlarmHandled`; a double re-arm since. Other
  /// stopped ids (the `alarmId == null` stop-everything fallback) have no
  /// `RingingWatch` of their own and are unaffected.
  void _handleAlarmOnce(int id) {
    if (id == widget.alarmId) {
      if (_ringingAlarmHandled) return;
      _ringingAlarmHandled = true;
    }
    (QrScanner.debugOnAlarmHandledOverride ?? Handler.onAlarmHandled)(
        _appState, id);
  }

  /// Idempotent (`ModalRoute.isCurrent`): a valid scan, Snooze and
  /// [RingingWatch] can all react to the same stop, and an unguarded second
  /// `Navigator.pop` would hit the navigator mid-transaction or pop the route
  /// underneath (docs/TODO.md T-147).
  void _closeView() {
    if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
      debugPrint('=====qrScanner: Navigator.pop(context) fired!');
    }
  }

  /// The emergency stop for when the camera cannot open the gate: a
  /// "guaranteed wake-up" alarm cannot be dismissed by scanning then, so
  /// stop the ringing alarm directly before letting the user leave this
  /// screen.
  ///
  /// docs/TODO.md T-216 (maintainer, 2026-10-06: "Wieso? der soll nur den
  /// aktuellen canceln."): this called `Alarm.stopAll()` from the initial
  /// commit on - from before T-74e gave the screen the ringing alarm's id,
  /// when stopping everything was the only way to reach the ringing one.
  /// That cancelled every armed alarm: scheduled ones came back at the next
  /// checkpoint, manual ones (since T-217) only once a checkpoint's
  /// `reconcileManualAlarmsWithPlatform` re-armed them - until then a manual
  /// alarm due in between stayed silent. Now it stops [QrScanner.alarmId],
  /// never a future alarm. The `alarmId == null` branch (stop exactly what
  /// the platform reports ringing) is unreachable in production: the only
  /// screen built without an id is `PageImportQr`, which shows Cancel
  /// (`displayExitButton`) instead of the emergency stop.
  ///
  /// `Alarm.stop` reports a failure as `false`, not as an exception, so each
  /// ring is checked again afterwards (as the valid-scan path does). If it
  /// still rings, `Alarm.stopAll()` is the last resort - cheap since T-217,
  /// for the reasons above. An alarm is handled ([_handleAlarmOnce], the
  /// valid-scan path: T-14 re-arm, T-147 once-only) only once it really
  /// stopped; if one still rings after that, the screen and the button stay
  /// - closing would leave a ringing alarm with no screen to stop it from
  /// (`androidStopAlarmOnDismiss: false`, and `Alarm.ringing` does not
  /// change, so nothing would bring a screen back).
  Future<void> _emergencyStopAndClose() async {
    List<int> ids;
    try {
      ids = switch (widget.alarmId) {
        final int id => <int>[id],
        null => await _appState.ringingPlatformAlarmIds(),
      };
    } catch (e) {
      debugPrint(
          '=====qrScanner: emergency stop: ringing alarms unknown: ${e.runtimeType}');
      ids = const <int>[];
    }

    for (final id in ids) {
      try {
        await _appState.stopPlatformAlarm(id);
      } catch (e) {
        debugPrint('=====qrScanner: emergency stop failed: ${e.runtimeType}');
      }
    }

    var stillRinging = await _stillRinging(ids);
    if (stillRinging.isNotEmpty) {
      debugPrint('=====qrScanner: emergency stop did not end the ring - '
          'stopping every alarm');
      try {
        await _appState.stopAllPlatformAlarms();
      } catch (e) {
        debugPrint(
            '=====qrScanner: stopping all alarms failed: ${e.runtimeType}');
      }
      stillRinging = await _stillRinging(ids);
    }

    for (final id in ids) {
      if (!stillRinging.contains(id)) _handleAlarmOnce(id);
    }
    if (stillRinging.isNotEmpty) {
      debugPrint('=====qrScanner: still ringing - keeping the screen open');
      return;
    }
    _closeView();
  }

  /// Which of [ids] the platform still reports ringing. A query that fails
  /// counts as "stopped": the stop call itself reported nothing wrong, and
  /// an unanswerable question must not trap the user behind
  /// `PopScope(canPop: false)`.
  Future<Set<int>> _stillRinging(List<int> ids) async {
    final ringing = <int>{};
    for (final id in ids) {
      try {
        if (await _appState.platformAlarmIsRinging(id)) ringing.add(id);
      } catch (e) {
        debugPrint('=====qrScanner: ringing state unknown: ${e.runtimeType}');
      }
    }
    return ringing;
  }
}
