import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'drive_vault_store.dart';

abstract interface class VaultSecrets {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureVaultSecrets implements VaultSecrets {
  const SecureVaultSecrets();
  static const storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  @override
  Future<String?> read(String key) =>
      storage.read(key: 'systock.drive.v2.$key');
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: 'systock.drive.v2.$key', value: value);
}

class VaultClaim {
  const VaultClaim({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.accountId,
    required this.installationId,
    this.parent,
  });
  final String id, companyId, companyName, accountId, installationId;
  final String? parent;
  Map<String, dynamic> toJson() => {
    'schema': 2,
    'id': id,
    'companyId': companyId,
    'companyName': companyName,
    'accountId': accountId,
    'installationId': installationId,
    'parent': parent,
  };
  factory VaultClaim.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 2)
      throw const FormatException('Formato de associação não suportado.');
    return VaultClaim(
      id: j['id'] as String,
      companyId: j['companyId'] as String,
      companyName: j['companyName'] as String,
      accountId: j['accountId'] as String,
      installationId: j['installationId'] as String,
      parent: j['parent'] as String?,
    );
  }
}

class DriveVaultIdentity {
  const DriveVaultIdentity(this.store, this.secrets);
  final DriveVaultStore store;
  final VaultSecrets secrets;
  Future<String> installationId() async {
    final saved = await secrets.read('installation');
    if (saved != null) return saved;
    final id = const Uuid().v4();
    await secrets.write('installation', id);
    return id;
  }

  Future<List<VaultClaim>> claims() async {
    final result = <String, VaultClaim>{};
    for (final file in await store.list('systock-v2-claim-')) {
      final claim = VaultClaim.fromJson(
        decodeVaultJson(await store.read(file.id)),
      );
      if (file.name != 'systock-v2-claim-${claim.id}.json')
        throw StateError('Associação inválida no Drive.');
      if (result.containsKey(claim.id) &&
          jsonEncode(result[claim.id]!.toJson()) != jsonEncode(claim.toJson()))
        throw StateError('Associações inconsistentes no Drive.');
      result[claim.id] = claim;
    }
    return result.values.toList();
  }

  /// A fork is rejected instead of choosing a winner by a client-side clock.
  static VaultClaim active(
    List<VaultClaim> all,
    String companyId,
    String accountId,
  ) {
    final chain = all.where((c) => c.companyId == companyId).toList();
    if (chain.isEmpty || chain.any((c) => c.accountId != accountId))
      throw StateError('A conta Google não corresponde à loja.');
    final roots = chain.where((c) => c.parent == null).toList();
    if (roots.length != 1)
      throw StateError(
        'Há associações concorrentes. A sincronização foi suspensa; contacte o suporte.',
      );
    var current = roots.single;
    final seen = <String>{};
    while (seen.add(current.id)) {
      final children = chain.where((c) => c.parent == current.id).toList();
      if (children.isEmpty) {
        if (seen.length != chain.length) break;
        return current;
      }
      if (children.length != 1) break;
      current = children.single;
    }
    throw StateError(
      'Transferências concorrentes detetadas. Contacte o suporte antes de sincronizar.',
    );
  }

  Future<void> publish(VaultClaim claim) async {
    await store.create(
      'systock-v2-claim-${claim.id}.json',
      utf8.encode(jsonEncode(claim.toJson())),
    );
    final current = active(await claims(), claim.companyId, claim.accountId);
    if (current.id != claim.id)
      throw StateError('A caixa principal mudou. Volte a ligar a loja.');
  }

  Future<void> assertWriter(VaultClaim expected) async {
    final current = active(
      await claims(),
      expected.companyId,
      expected.accountId,
    );
    if (current.id != expected.id ||
        current.installationId != await installationId()) {
      throw StateError(
        'Esta caixa foi substituída. Os dados locais foram preservados e o envio está bloqueado.',
      );
    }
  }
}
