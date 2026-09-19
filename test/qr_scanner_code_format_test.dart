import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/REQUIREMENTS.md R13: the deactivation-code scanner accepts any
// pre-existing code someone already has, not only a QR code this app itself
// generated - widened at the maintainer's request from `Format.qrCode` to
// `Format.any` (every 1D barcode and 2D matrix symbology zxing-cpp can
// decode: EAN/UPC/Code128/Codabar/ITF/GS1 DataBar, plus Aztec, Data Matrix,
// PDF417, MaxiCode and the Micro/rectangular Micro QR variants).
//
// A source-reading test, not a widget test, for the same reason
// cropPercent/tryHarder (docs/TODO.md T-143) cannot be exercised at runtime
// either: `ReaderWidget` needs a real camera, and every existing
// `QrScanner` test bypasses it entirely via `debugScanStreamOverride` -
// which is also why nothing there could have caught `codeFormat` regressing
// back to QR-only. This forbids that regression directly, the same
// "forbid the channel, not the symptom" reasoning as
// test/no_proprietary_dependencies_test.dart.
void main() {
  test('the scanner is configured to accept every symbology, not only QR',
      () {
    final source =
        File('lib/screens/scan_code/qr_scanner.dart').readAsStringSync();

    expect(source, contains('codeFormat: Format.any'),
        reason: 'ReaderWidget must not be restricted back to '
            'Format.qrCode - R13 requires any pre-existing code, including '
            'ordinary barcodes, to work');
  });
}
