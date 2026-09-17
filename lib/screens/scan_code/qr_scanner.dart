import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/screens/alarms/snooze_button.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/models/scan_code/scan_result.dart';

/// Pure comparison at the heart of the "guaranteed wake-up" gate: does the
/// scanned payload match the stored deactivation code? Extracted out of
/// [_QrScannerState] so it's unit-testable without a device - see
/// test/qr_scanner_validation_test.dart.
///
/// When [storedCode] is null there is nothing to validate against; this
/// fails open (returns true) to match the app's existing "illegal state"
/// behavior, which prioritizes not locking a user in behind a scanner over
/// enforcing a code that was never actually set.
bool isDeactivationCodeValid(DeactivationCode? storedCode, String? scannedPayload) {
  if (storedCode == null) {
    return true;
  }
  return storedCode.payload == scannedPayload;
}

class QrScanner extends StatefulWidget {
  final bool displayExitButton;

  /// docs/TODO.md T-74e: the id of the alarm that is actually ringing. Without
  /// it this screen had to `Alarm.stop` **every** saved alarm to silence the
  /// ringing one, which cancelled unrelated future alarms at the platform
  /// level while leaving `AppState`'s lists untouched - a divergence FR-18's
  /// sync could not see (it models "existing" from `AppState`). `null` keeps
  /// the old stop-everything behaviour as a fallback.
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

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> with WidgetsBindingObserver {
  StreamSubscription<Object?>? _subscription;
  late final AppState _appState;

  /// Set when the camera could not be opened at all (permission revoked,
  /// hardware busy, unsupported device). It drives the emergency stop button
  /// below - without it a "guaranteed wake-up" alarm whose scanner never
  /// initialises would leave the user on a `PopScope(canPop: false)` screen
  /// with no scanner and no way out.
  bool _cameraFailed = false;

  @override
  void initState() {
    debugPrint("=====initState: Creating new QRScannerState");
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
    // Start listening to lifecycle changes.
    WidgetsBinding.instance.addObserver(this);

    // The camera is driven by ReaderWidget in build(); only the injected test
    // stream needs a subscription here.
    _subscription = QrScanner.debugScanStreamOverride?.listen(_handleScan);
  }

  @override
  void dispose() {
    // Stop listening to lifecycle changes.
    WidgetsBinding.instance.removeObserver(this);

    // Stop listening to the injected events, if any. ReaderWidget disposes of
    // its own camera controller.
    unawaited(_subscription?.cancel());

    // Dispose the widget itself.
    super.dispose();
  }

  Future<void> _handleScan(ScanResult scan) async {
    if (mounted) {
      // A decode without text is a normal outcome for a blurred frame. It must
      // never be imported as a code of `null`, which nobody could reproduce.
      if (scan.payload == null) {
        return;
      }

      // IMPORT QR CODE IF NONE IS SET
      if (_appState.deactivationCode == null) {
        final data = scan.payload;
        // docs/TODO.md T-89: der Payload ist das Deaktivierungsgeheimnis -
        // wer diese Logzeile hat, kann den "garantierten" Wecker beliebig
        // aushebeln. Geloggt wird nur, DASS importiert wurde.
        debugPrint('=====qrScanner: Imported a deactivation code '
            '(${data == null ? 'empty' : 'non-empty'})');
        Diag.qrGate(outcome: QrOutcome.imported, codeWasSet: false);
        final newDeactivationCode = DeactivationCode(payload: data);
        setState(() {
          _appState.deactivationCode = newDeactivationCode;
        });
      }
      // VALIDATE QR CODE AND CLOSE OVERLAY ON SUCCESS
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
      // in case this state is reached, isDeactivationCodeValid already
      // returned true above to prevent the user being locked in ScanCode
      // View - nothing to stop, so there's nothing more to do here.
      debugPrint('=====qrValidator: ILLEGAL STATE!!!');
      return true;
    }

    // docs/TODO.md T-89: nur das Ergebnis, nie der Wert. Diese Zeile feuert
    // genau dann, wenn der Nutzer morgens den Alarm abschaltet - also
    // zuverlaessig jeden Tag.
    debugPrint('=====qrValidator: scanned code VALIDATED');
    // Kein Parameter fuer den Payload - auch keiner fuer dessen Laenge oder
    // Hash, beides waere ein Rueckweg zum Geheimnis.
    Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);

    try {
      // docs/TODO.md T-74e: stop exactly the ringing alarm when we know which
      // one it is, instead of every saved alarm.
      final ringingId = widget.alarmId;
      final List<int> idsToStop;
      if (ringingId != null) {
        idsToStop = [ringingId];
      } else {
        final alarmsSettings = await Alarm.getAlarms();
        idsToStop = alarmsSettings.map((a) => a.id).toList();
      }
      for (final id in idsToStop) {
        try {
          await Alarm.stop(id);
          Handler.onAlarmHandled(_appState, id);
        } catch (e) {
          debugPrint("=====ScreenAlarmActiveState: Failed to stop alarm: ${e.runtimeType}");
        }
      }
    } catch (e) {
      debugPrint('=====validateDeactivationCode: Error stopping alarms: ${e.runtimeType}');
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nothing to do any more: ReaderWidget starts and stops its own camera
    // with the lifecycle. The observer stays registered because the previous
    // scanner needed one, and removing the hook is a behaviour change worth
    // keeping visible rather than silently deleting.
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

    // Shown instead of the (hidden-by-design) exit button only when the
    // camera itself is unusable (permission revoked, hardware busy, unsupported
    // device, ...): without this, a "guaranteed wake-up" alarm whose QR
    // scanner can never initialize would leave the user stuck on a
    // PopScope(canPop: false) screen with no scanner and no way out.
    final emergencyStopButton = ElevatedButton.icon(
      onPressed: _emergencyStopAndClose,
      label: Text(
        'Stop alarm',
        style: TextStyle(color: _appState.accentColor),
      ),
      icon: Icon(Icons.notifications_off, color: _appState.accentColor),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // FR-20: Snooze braucht NIE den Code. Der Scan schaltet ab; Snooze
            // verschiebt nur - und zwar innerhalb eines Budgets, das den Termin
            // nicht gefaehrden kann. Einen Scan zu verlangen, um WEITER geweckt
            // zu werden, waere sinnlos und wuerde den Nutzer im Zweifel dazu
            // bringen, das Geraet ganz abzuschalten.
            // `alarmId` ist hier nullable: der Schirm wird auch zum blossen
            // Einlesen eines Codes geoeffnet, ohne dass etwas klingelt. Dann
            // gibt es nichts zu verschieben.
            if (widget.alarmId case final int ringingId)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SnoozeButton(
                    alarmId: ringingId,
                    onSnoozed: () {
                      if (context.mounted) Navigator.pop(context);
                    },
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
                  codeFormat: Format.qrCode,
                  // docs/TODO.md T-44: the gallery button is off, deliberately.
                  // Decoding a QR code from a stored image would let a user
                  // photograph the code once and defeat the "guaranteed
                  // wake-up" gate from bed. The camera is the point.
                  showGallery: false,
                  showFlashlight: true,
                  showToggleCamera: true,
                  scanDelaySuccess: const Duration(milliseconds: 500),
                  onScan: (code) => _handleScan(ScanResult(code.text)),
                  onControllerCreated: (controller, error) {
                    if (!mounted) return;
                    setState(() => _cameraFailed = error != null);
                    if (error != null) {
                      debugPrint(
                          '=====qrScanner: camera unavailable: ${error.runtimeType}');
                    }
                  },
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
                    else if (_cameraFailed)
                      emergencyStopButton,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeView() {
    if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
      debugPrint('=====qrScanner: Navigator.pop(context) fired!');
    }
  }

  // Fallback for when the camera itself has failed: a "guaranteed wake-up"
  // alarm cannot be dismissed by scanning, so stop all ringing alarms
  // directly (mirroring Handler.handleAlarm's own "no overlay could be
  // shown" fallback) before letting the user leave this screen.
  Future<void> _emergencyStopAndClose() async {
    try {
      await Alarm.stopAll();
    } catch (e) {
      debugPrint('=====qrScanner: Failed to stop all alarms: ${e.runtimeType}');
    }
    _closeView();
  }
}
