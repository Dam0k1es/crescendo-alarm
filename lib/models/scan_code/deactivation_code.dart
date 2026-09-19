import 'dart:convert';
import 'dart:math';

class DeactivationCode {
  late final String payload;

  /// A free-text reminder of what to scan, entered by the user themselves -
  /// not the code's content. A QR code re-rendered from a scanned-in
  /// payload looks nothing like the physical code that was actually
  /// scanned (the same text has many equally valid QR encodings, chosen
  /// independently by whichever encoder produced each one), so showing
  /// that re-rendered image back to the user doesn't help them remember
  /// what to scan next time. `null` until the user sets one.
  String? description;

  // Initialize payload in constructor
  DeactivationCode({String? payload, this.description}) {
    this.payload = payload ?? generateRandomHash();
  }

  static String generateRandomHash() {
    // Create a secure random object
    final random = Random.secure();
    // Generate 16 random bytes (128 bits)
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Convert bytes to a hex string (common representation for hashes)
    final hash = base64Encode(bytes); // You can also use base16Encode for hex
    return hash;
  }

  String toJson() {
    return jsonEncode({
      'payload': payload,
      'description': description,
    });
  }

  factory DeactivationCode.fromJson(String jsonString) {
    final data = jsonDecode(jsonString);
    final payload = data['payload'];
    // Absent for data saved before this field existed - falls back to null
    // rather than throwing.
    final description = data['description'] as String?;
    return DeactivationCode(payload: payload, description: description);
  }
}
