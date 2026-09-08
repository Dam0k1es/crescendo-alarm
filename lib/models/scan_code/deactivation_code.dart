import 'dart:convert';
import 'dart:math';

class DeactivationCode {
  late final String payload;

  // Initialize payload in constructor
  DeactivationCode({String? payload}) {
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
    });
  }

  factory DeactivationCode.fromJson(String jsonString) {
    final data = jsonDecode(jsonString);
    final payload = data['payload'];
    return DeactivationCode(payload: payload);
  }
}
