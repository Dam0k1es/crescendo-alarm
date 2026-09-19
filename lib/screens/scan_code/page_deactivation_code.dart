import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/scan_code/page_import_qr.dart';
import 'package:wakeywakey/utils/utils.dart';

class PageDeactivationCode extends StatefulWidget {
  const PageDeactivationCode({super.key});

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
      semanticsLabel: 'WakeyWakey Deactivation Code',
      //errorCorrectionLevel: QrErrorCorrectLevel.M,
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
      onPressed: () {
        // TODO: trigger print function here
        displayToast(context, 'This is a future feature!');
      },
      icon: Icon(Icons.share, color: _appState.accentColor),
      label: Text(
        'Share',
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
                  // exported from WakeyWakey itself.
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
                  //importQrCodeButton,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        removeCodeButton,
                        const Spacer(),
                        shareCodeButton,
                        const Spacer(),
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
