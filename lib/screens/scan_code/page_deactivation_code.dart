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

  @override
  Widget build(BuildContext context) {
    _displayArea = MediaQuery.of(context).size.width * 0.75;

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
                    'Currently no deactivation code configured. Generate or import to activate this feature!',
                    style: TextStyle(fontSize: 18),
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
        if (_appState.deactivationCode != null)
          Center(
            child: SizedBox(
              width: _displayArea,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _generateQrImageView(_appState.deactivationCode!),
                  const SizedBox(height: 20),
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
      ],
    );
  }
}
