import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/screens/alarms/snooze_button.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/scan_code/scanned_barcode_label.dart';
import 'package:wakeywakey/screens/scan_code/scanner_button_widgets.dart';
import 'package:wakeywakey/screens/scan_code/scanner_error_widget.dart';
import 'package:wakeywakey/screens/scan_code/scanner_overlay.dart';

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

  /// Test-only seam: when set, this stream is used by every `QrScanner`
  /// instance instead of the real camera's
  /// [MobileScannerController.barcodes]. It's a static field (not a
  /// constructor parameter) because production code
  /// (`Handler.handleAlarm`) constructs `QrScanner()` directly with no way
  /// to thread a parameter through - E2E tests instead set this before
  /// triggering the alarm-ringing flow, to exercise the deactivation logic
  /// (`_handleBarcode`/`_validateDeactivationCode`) without simulating an
  /// actual camera feed (mobile_scanner's native camera preview isn't
  /// something integration_test can drive directly). Never set outside of
  /// tests; must be reset to null in the test's `tearDown`.
  @visibleForTesting
  static Stream<BarcodeCapture>? debugBarcodeStreamOverride;

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> with WidgetsBindingObserver {
  final MobileScannerController controller = MobileScannerController(
    // required options for the scanner
    formats: const [BarcodeFormat.qrCode],
  );

  StreamSubscription<Object?>? _subscription;
  Barcode? _barcode;
  late final AppState _appState;

  @override
  void initState() {
    debugPrint("=====initState: Creating new QRScannerState");
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
    // Start listening to lifecycle changes.
    WidgetsBinding.instance.addObserver(this);

    // Start listening to the barcode events (or the injected test stream).
    _subscription =
        (QrScanner.debugBarcodeStreamOverride ?? controller.barcodes)
            .listen(_handleBarcode);

    if (QrScanner.debugBarcodeStreamOverride != null) {
      // Test mode: never touch the real camera.
      return;
    }

    // Start existing scanner if it was running.
    try {
      unawaited(controller.stop());
    } catch (e) {
      debugPrint('=====initState: Error stopping scanner: ${e.runtimeType}');
    }

    // Finally, start the scanner itself.
    try {
      unawaited(controller.start());
    } catch (e) {
      debugPrint('=====initState: Error starting scanner: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    // Stop listening to lifecycle changes.
    WidgetsBinding.instance.removeObserver(this);

    // Stop listening to the barcode events.
    unawaited(_subscription?.cancel());

    //_subscription = null;

    // Finally, dispose of the controller.
    unawaited(controller.stop());
    unawaited(controller.dispose());

    // Dispose the widget itself.
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture barcodes) async {
    if (mounted) {
      setState(() {
        _barcode = barcodes.barcodes.firstOrNull;
        if (_barcode == null) {
          return;
        }
      });

      // IMPORT QR CODE IF NONE IS SET
      if (_appState.deactivationCode == null) {
        final data = _barcode!.rawValue;
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
          validationSuccessful = await _validateDeactivationCode(_barcode!);
        } catch (e) {
          debugPrint(
              '=====handleBarcode: Error validating Deactivation Code: ${e.runtimeType}');
        }
        if (validationSuccessful) {
          _closeView();
        }
      }
    } // end of 'if mounted'
  }

  Future<bool> _validateDeactivationCode(Barcode barcode) async {
    // Validate the scanned code BEFORE stopping any alarms, so a wrong or
    // arbitrary QR code can never silently disarm the alarm.
    if (!isDeactivationCodeValid(_appState.deactivationCode, barcode.rawValue)) {
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
    // If the controller is not ready, do not try to start or stop it.
    // Permission dialogs can trigger lifecycle changes before the controller is ready.
    if (!controller.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        // Restart the scanner when the app is resumed.
        // Don't forget to resume listening to the barcode events.
        _subscription = controller.barcodes.listen(_handleBarcode);

        unawaited(controller.start());
      case AppLifecycleState.inactive:
        // Stop the scanner when the app is paused.
        // Also stop the barcode events subscription.
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(controller.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanWindow = Rect.fromCenter(
      center: MediaQuery.sizeOf(context).center(Offset.zero),
      width: 200,
      height: 200,
    );

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
            Center(
              child: MobileScanner(
                fit: BoxFit.contain,
                controller: controller,
                scanWindow: scanWindow,
                errorBuilder: (context, error) {
                  return ScannerErrorWidget(error: error);
                },
                overlayBuilder: (context, constraints) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: widget.displayExitButton
                          ? const SizedBox()
                          : ScannedBarcodeLabel(barcodes: controller.barcodes),
                    ),
                  );
                },
              ),
            ),
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, child) {
                if (!value.isInitialized ||
                    !value.isRunning ||
                    value.error != null) {
                  return const SizedBox();
                }

                return CustomPaint(
                  painter: ScannerOverlay(scanWindow: scanWindow),
                );
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    final bool cameraFailed = value.error != null;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ToggleFlashlightButton(controller: controller),
                        if (widget.displayExitButton)
                          exitButton
                        else if (cameraFailed)
                          emergencyStopButton,
                        SwitchCameraButton(controller: controller),
                      ],
                    );
                  },
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
