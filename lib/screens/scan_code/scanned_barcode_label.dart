import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Zeigt **nur**, dass ein Code erkannt wurde - niemals dessen Wert.
///
/// docs/TODO.md T-89: der Rohwert ist das Deaktivierungsgeheimnis, mit dem sich
/// der "garantierte" Wecker aushebeln laesst. Dieses Label wird im
/// Alarm-Modus angezeigt (qr_scanner.dart:298-300, `displayExitButton == false`),
/// also gross auf dem Bildschirm eines klingelnden Geraets - wer daneben steht
/// oder ein Foto macht, haette den Code sonst dauerhaft.
class ScannedBarcodeLabel extends StatelessWidget {
  const ScannedBarcodeLabel({
    super.key,
    required this.barcodes,
  });

  final Stream<BarcodeCapture> barcodes;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: barcodes,
      builder: (context, snapshot) {
        final scannedBarcodes = snapshot.data?.barcodes ?? [];

        if (scannedBarcodes.isEmpty) {
          return const Text(
            'Scan a QR Code!',
            overflow: TextOverflow.fade,
            style: TextStyle(color: Colors.white),
          );
        }

        return const Text(
          'QR Code detected',
          overflow: TextOverflow.fade,
          style: TextStyle(color: Colors.white),
        );
      },
    );
  }
}
