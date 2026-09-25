import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';

// User request: the QR code re-rendered from a scanned-in payload looks
// nothing like the physical code that was actually scanned (a QR code is
// one of many valid encodings of the same text, so two different encoders
// producing the same payload never look alike) - so a user has no way to
// remember what to scan next time. A free-text description, entered once
// by the user, replaces that unhelpful re-rendered image on screen.
void main() {
  test('defaults to no description', () {
    final code = DeactivationCode(payload: 'abc');
    expect(code.description, isNull);
  });

  test('carries a description through toJson/fromJson', () {
    final code =
        DeactivationCode(payload: 'abc', description: 'Barcode on the milk carton');
    final roundTripped = DeactivationCode.fromJson(code.toJson());

    expect(roundTripped.payload, 'abc');
    expect(roundTripped.description, 'Barcode on the milk carton');
  });

  test('fromJson tolerates data saved before description existed', () {
    // A pre-existing installation's stored JSON has no 'description' key at
    // all - must not throw, and must come back as null rather than some
    // sentinel.
    final roundTripped = DeactivationCode.fromJson('{"payload":"abc"}');

    expect(roundTripped.payload, 'abc');
    expect(roundTripped.description, isNull);
  });
}
