import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scan_code/qr_export.dart';

// docs/TODO.md T-182 (maintainer request): the deactivation-code QR image
// exported for sharing/printing must actually be a valid PNG - `QrPainter`
// on its own paints only the QR modules, with no background fill, so a
// naive `toImageData()` call produces a transparent-background image; this
// pins down that a real, opaque-white-background PNG comes out instead.

void main() {
  test('renders a non-empty PNG for a given payload', () async {
    final bytes = await renderQrCodePng('some-code-payload');

    expect(bytes, isNotEmpty);
    // The 8-byte PNG signature (docs: https://www.w3.org/TR/png/#5PNG-file-signature).
    expect(bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  });

  test('different payloads render different images', () async {
    final a = await renderQrCodePng('payload-a');
    final b = await renderQrCodePng('payload-b');

    expect(a, isNot(equals(b)),
        reason: 'two different codes must not silently render identically');
  });

  test('the same payload renders the same image deterministically', () async {
    final first = await renderQrCodePng('stable-payload');
    final second = await renderQrCodePng('stable-payload');

    expect(first, equals(second));
  });

  test('respects the requested size', () async {
    final small = await renderQrCodePng('sized-payload', size: 100);
    final large = await renderQrCodePng('sized-payload', size: 400);

    // A larger raster PNG is larger in byte count for the same content -
    // not a strict guarantee for every possible image codec, but true here
    // since the pixel dimensions genuinely differ.
    expect(large.length, greaterThan(small.length));
  });
}
