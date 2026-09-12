import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class VaultCipher {
  static final algorithm = AesGcm.with256bits();
  static Future<String> newRecoveryKey() async =>
      base64UrlEncode(await (await algorithm.newSecretKey()).extractBytes());
  static SecretKey parseKey(String text) {
    final bytes = base64Url.decode(text.trim());
    if (bytes.length != 32)
      throw const FormatException('A chave de recuperação é inválida.');
    return SecretKey(bytes);
  }

  static Future<List<int>> encrypt(
    List<int> bytes,
    String key,
    String companyId,
  ) async {
    final box = await algorithm.encrypt(
      bytes,
      secretKey: parseKey(key),
      aad: utf8.encode('systock-v2:$companyId'),
    );
    return utf8.encode(
      jsonEncode({
        'version': 2,
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'data': base64Encode(box.cipherText),
      }),
    );
  }

  static Future<Uint8List> decrypt(
    List<int> bytes,
    String key,
    String companyId,
  ) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['version'] != 2)
      throw const FormatException('Versão de backup não suportada.');
    final plain = await algorithm.decrypt(
      SecretBox(
        base64Decode(j['data'] as String),
        nonce: base64Decode(j['nonce'] as String),
        mac: Mac(base64Decode(j['mac'] as String)),
      ),
      secretKey: parseKey(key),
      aad: utf8.encode('systock-v2:$companyId'),
    );
    return Uint8List.fromList(plain);
  }
}
