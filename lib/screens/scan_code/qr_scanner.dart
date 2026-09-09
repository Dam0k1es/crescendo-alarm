import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
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

  const QrScanner({
    super.key,
    this.displayExitButton = false,
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
      debugPrint('=====initState: Error stopping scanner: $e');
    }

    // Finally, start the scanner itself.
    try {
      unawaited(controller.start());
    } catch (e) {
      debugPrint('=====initState: Error starting scanner: $e');
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
        debugPrint('=====qrScanner: Imported QR code data: $data');
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
              '=====handleBarcode: Error validating Deactivation Code: $e');
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

    debugPrint(
        '=====qrValidator: Scanned QR code data: ${barcode.rawValue}; VALIDATED!');

    try {
      List<AlarmSettings> alarmsSettings = await Alarm.getAlarms();
      for (AlarmSettings alarmSetting in alarmsSettings) {
        try {
          await Alarm.stop(alarmSetting.id);
          Handler.onAlarmHandled(_appState, alarmSetting.id);
        } catch (e) {
          debugPrint("=====ScreenAlarmActiveState: Failed to stop alarm: $e");
        }
      }
    } catch (e) {
      debugPrint('=====validateDeactivationCode: Error stopping alarms: $e');
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
      debugPrint('=====qrScanner: Failed to stop all alarms: $e');
    }
    _closeView();
  }
}
