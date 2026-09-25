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

/// One decoded scan, in the app's own terms.
///
/// docs/TODO.md T-33: the scanner package used to reach deep into the app -
/// `BarcodeCapture` and `Barcode` from `mobile_scanner` appeared in the QR
/// screen's public test seam, in four widgets and in the E2E suite. Replacing
/// the scanner therefore touched all of them, which is precisely the cost that
/// made the licence problem feel expensive to fix.
///
/// So the app now names its own type at that boundary. Everything outside
/// `lib/screens/scan_code/` sees only this, and the next swap of a scanner
/// library is a change in one file.
class ScanResult {
  const ScanResult(this.payload);

  /// The decoded text, or `null` when the decoder produced no text - which is
  /// a normal outcome for a blurred frame and must never be mistaken for an
  /// empty code.
  final String? payload;

  @override
  bool operator ==(Object other) =>
      other is ScanResult && other.payload == payload;

  @override
  int get hashCode => payload.hashCode;

  @override
  String toString() =>
      // Deliberately without the payload: it is the deactivation secret
      // (docs/TODO.md T-89).
      'ScanResult(${payload == null ? 'empty' : 'non-empty'})';
}
