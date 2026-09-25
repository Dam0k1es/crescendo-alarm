import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';

// Pure-logic tests for the QR deactivation code comparison, extracted out of
// _QrScannerState so it's testable without a device. This is the app's one
// differentiating security property - a wrong or arbitrary QR code must
// never validate.
void main() {
  group('isDeactivationCodeValid', () {
    test('matching payload is valid', () {
      final code = DeactivationCode(payload: 'correct-code');
      expect(isDeactivationCodeValid(code, 'correct-code'), isTrue);
    });

    test('non-matching payload is invalid', () {
      final code = DeactivationCode(payload: 'correct-code');
      expect(isDeactivationCodeValid(code, 'wrong-code'), isFalse);
    });

    test('a scanned code that is a prefix of the real one is invalid', () {
      final code = DeactivationCode(payload: 'correct-code');
      expect(isDeactivationCodeValid(code, 'correct-cod'), isFalse);
    });

    test('null scanned payload is invalid when a code is stored', () {
      final code = DeactivationCode(payload: 'correct-code');
      expect(isDeactivationCodeValid(code, null), isFalse);
    });

    test('no code stored fails open (matches existing "illegal state" behavior)', () {
      expect(isDeactivationCodeValid(null, 'anything'), isTrue);
    });

    test('no code stored fails open even for a null scanned payload', () {
      expect(isDeactivationCodeValid(null, null), isTrue);
    });
  });
}
