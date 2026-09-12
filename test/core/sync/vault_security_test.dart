import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/sync/drive_vault_identity.dart';
import 'package:systock/core/sync/drive_vault_store.dart';
import 'package:systock/core/sync/vault_cipher.dart';

class _MemorySecrets implements VaultSecrets {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryStore implements DriveVaultStore {
  final values = <String, Uint8List>{};
  @override
  Future<List<VaultFile>> list(String prefix) async => [
    for (final entry in values.entries)
      if (entry.key.startsWith(prefix))
        VaultFile(entry.key, entry.key, DateTime.utc(2026)),
  ];
  @override
  Future<Uint8List> read(String id) async => values[id]!;
  @override
  Future<String> create(String name, List<int> bytes) async {
    values[name] = Uint8List.fromList(bytes);
    return name;
  }

  @override
  Future<void> delete(String id) async => values.remove(id);
}

void main() {
  test(
    'encrypted vault rejects a wrong key and preserves authenticated data',
    () async {
      final key = await VaultCipher.newRecoveryKey();
      final encrypted = await VaultCipher.encrypt([1, 2, 3], key, 'company');
      expect(await VaultCipher.decrypt(encrypted, key, 'company'), [1, 2, 3]);
      final wrongKey = await VaultCipher.newRecoveryKey();
      expect(
        () => VaultCipher.decrypt(encrypted, wrongKey, 'company'),
        throwsA(anything),
      );
    },
  );

  test('identity rejects a forked transfer chain', () async {
    final store = _MemoryStore();
    final secrets = _MemorySecrets();
    final identity = DriveVaultIdentity(store, secrets);
    const root = VaultClaim(
      id: 'root',
      companyId: 'company',
      companyName: 'Loja',
      accountId: 'account',
      installationId: 'one',
    );
    await identity.publish(root);
    const childA = VaultClaim(
      id: 'a',
      companyId: 'company',
      companyName: 'Loja',
      accountId: 'account',
      installationId: 'two',
      parent: 'root',
    );
    const childB = VaultClaim(
      id: 'b',
      companyId: 'company',
      companyName: 'Loja',
      accountId: 'account',
      installationId: 'three',
      parent: 'root',
    );
    store.values['systock-v2-claim-a.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(childA.toJson())),
    );
    store.values['systock-v2-claim-b.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(childB.toJson())),
    );
    final claims = await identity.claims();
    expect(
      () => DriveVaultIdentity.active(claims, 'company', 'account'),
      throwsA(anything),
    );
  });
}
