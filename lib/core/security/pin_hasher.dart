import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class PinDigest {
  const PinDigest(this.hashBase64, this.saltBase64);
  final String hashBase64, saltBase64;
}

class PinHasher {
  PinHasher({Pbkdf2? algorithm})
    : _algorithm =
          algorithm ??
          Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);
  final Pbkdf2 _algorithm;
  Future<PinDigest> hash(String pin) async {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain 4 to 12 digits');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return PinDigest(
      base64Encode(await key.extractBytes()),
      base64Encode(salt),
    );
  }

  Future<bool> verify(String pin, PinDigest digest) async {
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: base64Decode(digest.saltBase64),
    );
    final actual = await key.extractBytes(),
        expected = base64Decode(digest.hashBase64);
    if (actual.length != expected.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }
}
