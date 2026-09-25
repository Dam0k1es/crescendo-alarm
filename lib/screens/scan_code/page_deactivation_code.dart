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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/models/scan_code/qr_export.dart';
import 'package:crescendo_alarm/screens/scan_code/page_import_qr.dart';
import 'package:crescendo_alarm/utils/utils.dart';

class PageDeactivationCode extends StatefulWidget {
  const PageDeactivationCode({super.key});

  /// Test seam: replaces the real `Share.shareXFiles` call (share_plus has
  /// no platform channel in `flutter test`) - same pattern as
  /// `ScreenSleephabits.debugTimePickerOverride`. Receives the rendered PNG
  /// bytes.
  @visibleForTesting
  static Future<void> Function(List<int> pngBytes)? debugShareOverride;

  /// Test seam: replaces the real `Printing.layoutPdf` call.
  @visibleForTesting
  static Future<void> Function(List<int> pngBytes)? debugPrintOverride;

  /// Test seam: replaces the real [renderQrCodePng] call. `test/qr_export_test
  /// .dart` already covers that function itself in isolation (a plain
  /// `test()`, not `testWidgets()`); its `dart:ui` image rasterization
  /// (`Picture.toImage`/`Image.toByteData`) never resolves when triggered
  /// from inside an active `testWidgets` binding via a real button tap - not
  /// even inside `tester.runAsync` - so widget tests that only need to check
  /// the Share/Print *wiring* use a fast, deterministic fake here instead of
  /// re-exercising the real rendering pipeline.
  @visibleForTesting
  static Future<Uint8List> Function(String payload)? debugRenderQrCodeOverride;

  @override
  State<PageDeactivationCode> createState() => _PageDeactivationCodeState();
}

class _PageDeactivationCodeState extends State<PageDeactivationCode> {
  late final AppState _appState;

  // must not be final, because of reinitialization on rebuild:
  late double _displayArea;

  /// The payload of the code the description prompt has already been shown
  /// for - keyed by payload, not a bare bool, so a *new* code (Generate
  /// after Remove, or a fresh Import) is prompted for again, while
  /// rebuilding this screen for the SAME code doesn't reopen the dialog on
  /// every frame.
  String? _promptedForPayload;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
  }

  QrImageView _generateQrImageView(DeactivationCode code) {
    return QrImageView(
      data: code.payload,
      version: QrVersions.auto,
      size: _displayArea,
      backgroundColor: Colors.white,
      semanticsLabel: 'Crescendo Alarm Deactivation Code',
    );
  }

  /// User request: a QR code re-rendered from a scanned-in payload looks
  /// nothing like the code that was actually scanned, so it's useless as a
  /// reminder of what to scan next time. This lets the user write that
  /// reminder themselves instead.
  Future<void> _showDescriptionDialog(DeactivationCode code) async {
    final controller = TextEditingController(text: code.description ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What do you need to scan?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. "Barcode on the milk carton"',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog's own closing transition can still be
    // reading the controller through its TextField at the moment this
    // `await` resumes, and disposing immediately raced it ("A
    // TextEditingController was used after being disposed"). The dialog and
    // its TextField are short-lived and go out of scope with it regardless.
    if (!mounted || result == null) return;

    // Re-fetch the current code rather than closing over the one passed in:
    // the dialog is asynchronous, and only the payload identifies which
    // code this description belongs to.
    final current = _appState.deactivationCode;
    if (current == null || current.payload != code.payload) return;
    _appState.deactivationCode =
        DeactivationCode(payload: current.payload, description: result.trim());
  }

  /// docs/TODO.md T-182 (maintainer request): shares the deactivation code
  /// as a PNG via the native Android share sheet (share_plus wraps
  /// `Intent.ACTION_SEND` - no external app is required, the OS's own
  /// chooser is the mechanism; the user picks whatever target they want
  /// from it). Reads `_appState.deactivationCode` directly rather than
  /// whatever `page_deactivation_code.dart` happens to have on screen right
  /// now (the QR image, or the user's own description once one exists) -
  /// the export always reflects the actual code.
  Future<void> _shareQrCode() async {
    final code = _appState.deactivationCode;
    if (code == null) return;
    try {
      final pngBytes = await (PageDeactivationCode.debugRenderQrCodeOverride ??
              renderQrCodePng)(code.payload);
      if (PageDeactivationCode.debugShareOverride != null) {
        await PageDeactivationCode.debugShareOverride!(pngBytes);
        return;
      }
      // No accompanying text: the QR image already carries the secret, and
      // a caption naming what it's for would be all a screenshot of the
      // share sheet needs to identify it. XFile.fromData needs no temp
      // file of its own - share_plus reads the bytes directly.
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(pngBytes,
              name: 'deactivation_code.png', mimeType: 'image/png'),
        ],
      ));
    } catch (e) {
      debugPrint('=====pageDeactivationCode: share failed: ${e.runtimeType}');
      if (mounted) displayToast(context, 'Could not share the QR code.');
    }
  }

  /// docs/TODO.md T-182 (maintainer request, "wichtig wäre mir den QR Code
  /// an einen Drucker senden zu können"): prints the deactivation code
  /// directly via `android.print.PrintManager` (through the `printing`/`pdf`
  /// packages) - the OS's own print framework, not dependent on whether a
  /// print target happens to be registered in the generic share sheet
  /// `_shareQrCode` uses. `pdf` is needed only because that is the document
  /// format Android's print framework itself expects; the underlying
  /// content is the same PNG `_shareQrCode` exports.
  Future<void> _printQrCode() async {
    final code = _appState.deactivationCode;
    if (code == null) return;
    try {
      final pngBytes = await (PageDeactivationCode.debugRenderQrCodeOverride ??
              renderQrCodePng)(code.payload);
      if (PageDeactivationCode.debugPrintOverride != null) {
        await PageDeactivationCode.debugPrintOverride!(pngBytes);
        return;
      }
      final document = pw.Document();
      final image = pw.MemoryImage(Uint8List.fromList(pngBytes));
      document.addPage(pw.Page(
        build: (context) => pw.Center(child: pw.Image(image)),
      ));
      await Printing.layoutPdf(onLayout: (format) async => document.save());
    } catch (e) {
      debugPrint('=====pageDeactivationCode: print failed: ${e.runtimeType}');
      if (mounted) displayToast(context, 'Could not print the QR code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Real-device report: after importing a code via the QR scanner
    // (`PageImportQr`, a separate pushed route/widget), this screen kept
    // showing "no code configured" until something else happened to rebuild
    // it - `_appState` was read with `listen: false` in initState, so
    // AppState.notifyListeners() from that other widget's mutation had no
    // way to reach this screen; only the Generate/Remove buttons' own local
    // `setState` calls masked the same gap for themselves. Subscribing here
    // makes this screen react to a `deactivationCode` change no matter which
    // widget made it.
    context.watch<AppState>();
    _displayArea = MediaQuery.of(context).size.width * 0.75;

    // User request: prompt for a description the moment a code with none
    // appears - whether just imported or just generated - rather than
    // leaving the (unhelpful, re-rendered) QR image as the only thing shown
    // until the user thinks to add one themselves. Scheduled for after this
    // frame, not called directly here: `showDialog` during `build()` would
    // try to open a route while the widget tree is still being built.
    final currentCode = _appState.deactivationCode;
    if (currentCode != null &&
        (currentCode.description == null || currentCode.description!.isEmpty) &&
        _promptedForPayload != currentCode.payload) {
      _promptedForPayload = currentCode.payload;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDescriptionDialog(currentCode);
      });
    }

    final generateCodeButton = ElevatedButton.icon(
      onPressed: () {
        setState(() {
          final newCode = DeactivationCode();
          _appState.deactivationCode = newCode;
          // docs/TODO.md T-89: this is where the secret is BORN - a log
          // snapshot from this point on would be permanently sufficient.
          // Only log the fact.
          debugPrint('=====pageDeactivationCode: new QR code generated');
        });
      },
      icon: Icon(
        Icons.change_circle,
        color: _appState.accentColor,
      ),
      label: Text(
        'Generate',
        style: TextStyle(color: _appState.accentColor),
      ),
    );

    final removeCodeButton = ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _appState.deactivationCode = null;
        });
      },
      icon: Icon(Icons.delete_forever_rounded, color: _appState.accentColor),
      label: Text(
        'Remove',
        style: TextStyle(color: _appState.accentColor),
      ),
    );

    final shareCodeButton = OutlinedButton.icon(
      onPressed: _shareQrCode,
      icon: Icon(Icons.share, color: _appState.accentColor),
      label: Text(
        'Share',
        style: TextStyle(color: _appState.accentColor),
      ),
    );

    final printCodeButton = OutlinedButton.icon(
      onPressed: _printQrCode,
      icon: Icon(Icons.print, color: _appState.accentColor),
      label: Text(
        'Print',
        style: TextStyle(color: _appState.accentColor),
      ),
    );

    final importCodeButton = OutlinedButton.icon(
      onPressed: () {
        showFullScreenOverlay(context, const PageImportQr());
      },
      icon: Icon(Icons.camera_alt, color: _appState.accentColor),
      label: Text('Import', style: TextStyle(color: _appState.accentColor)),
    );

    return PageView(
      children: [
        // No Deactivation Code
        if (_appState.deactivationCode == null)
          Center(
            child: SizedBox(
              width: _displayArea,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Currently no deactivation code configured. Generate a new one, or import to activate this feature!',
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // docs/REQUIREMENTS.md R13: "Import" isn't limited to a
                  // code this app generated, or even to QR codes - any QR
                  // code or barcode already at hand works, verbatim. Without
                  // saying so, "Import" reads like it only accepts a QR code
                  // exported from Crescendo Alarm itself.
                  Text(
                    'Import works with any QR code or barcode you already '
                    'have - it does not have to come from this app.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      generateCodeButton,
                      const Spacer(),
                      importCodeButton,
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Deactivation Code Set
        //
        // The QR image's size is derived from screen WIDTH alone
        // (`_displayArea`), with no regard for available height - on a wide
        // but short screen (a small phone, or landscape) that image plus the
        // button row below it can be taller than the screen, which used to
        // overflow rather than scroll.
        if (_appState.deactivationCode != null)
          Center(
            child: SingleChildScrollView(
              child: SizedBox(
                width: _displayArea,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // User request: once a description exists, show THAT
                    // instead of the re-rendered QR image - the image is not
                    // a picture of what to scan (see DeactivationCode.
                    // description's doc comment), so it doesn't belong here
                    // once something more useful is available.
                    if (_appState.deactivationCode!.description
                            case final description?
                        when description.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: _appState.accentColor),
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Text(
                          description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20),
                        ),
                      )
                    else
                      _generateQrImageView(_appState.deactivationCode!),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          _showDescriptionDialog(_appState.deactivationCode!),
                      icon: Icon(Icons.edit_note, color: _appState.accentColor),
                      label: Text(
                        (_appState.deactivationCode!.description ?? '').isEmpty
                            ? 'Add a description'
                            : 'Edit description',
                        style: TextStyle(color: _appState.accentColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // docs/TODO.md T-182: a `Wrap`, not a `Row` of
                    // `Spacer`s - three buttons (was two) risk overflowing a
                    // narrow phone width the way a fixed `Row` cannot
                    // recover from, matching the lesson T-176 already found
                    // the hard way for a different dialog's button row.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        removeCodeButton,
                        shareCodeButton,
                        printCodeButton,
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
