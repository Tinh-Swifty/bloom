import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// The shared secret of a pair: both phones enter the same code and derive
/// the same encryption key and channel name from it. The code never leaves
/// the two devices.
class Pairing {
  // No 0/O/1/I so the code is easy to read aloud.
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const codeLength = 12;

  static String generateCode([Random? random]) {
    final rnd = random ?? Random.secure();
    final raw = List.generate(
      codeLength,
      (_) => alphabet[rnd.nextInt(alphabet.length)],
    ).join();
    return _format(raw);
  }

  /// Returns the code as XXXX-XXXX-XXXX, or null if [input] is not a code.
  static String? normalize(String input) {
    final raw = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (raw.length != codeLength) return null;
    if (raw.split('').any((c) => !alphabet.contains(c))) return null;
    return _format(raw);
  }

  static String _format(String raw) =>
      '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8)}';

  static Future<Room> derive(String code) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 20000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: utf8.encode('bennhau/v1'),
    );
    final keyBytes = await key.extractBytes();
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('topic'),
      secretKey: SecretKeyData(keyBytes),
    );
    final topic = mac.bytes
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return Room(topic: 'bennhau/$topic', key: SecretKeyData(keyBytes));
  }
}

/// Channel + key of a pair. Everything sent to the relay server is
/// AES-256-GCM encrypted, so the server only ever sees opaque bytes.
class Room {
  Room({required this.topic, required this.key});

  final String topic;
  final SecretKey key;

  static final _aes = AesGcm.with256bits();

  /// [senderId] is authenticated with the message so one device's message
  /// cannot be replayed as if it came from another.
  Future<String> encrypt(Map<String, dynamic> json, String senderId) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(json)),
      secretKey: key,
      aad: utf8.encode(senderId),
    );
    return base64Encode(box.concatenation());
  }

  /// Returns null when [payload] was not produced with this room's key.
  Future<Map<String, dynamic>?> decrypt(String payload, String senderId) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(payload),
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _aes.decrypt(
        box,
        secretKey: key,
        aad: utf8.encode(senderId),
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
