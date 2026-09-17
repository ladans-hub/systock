import 'package:crypto/crypto.dart';
import 'package:systock/core/licensing/license_service.dart';
import 'package:sqlite3/sqlite3.dart' as native;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'drive_replica_sync.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/backup/backup_service.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';
import 'drive_vault_store.dart';
import 'drive_vault_identity.dart';
import 'vault_cipher.dart';
import 'vault_backup.dart';

/// Serializes connect, backup, disconnect and restore within this process.
class VaultLock {
  static Future<void> _tail = Future.value();
  static Future<T> run<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

class DriveVaultService {
  DriveVaultService(
    this.db,
    this.store,
    this.secrets,
    this.documents, {
    required this.accountId,
    required this.email,
  });
  final AppDatabase db;
  final DriveVaultStore store;
  final VaultSecrets secrets;
  final Directory documents;
  final String accountId, email;
  DriveVaultIdentity get identity => DriveVaultIdentity(store, secrets);
  static const bindingSetting = 'sync.drive_v2';
  static Future<Map<String, dynamic>?> binding(AppDatabase db) async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(bindingSetting))).getSingleOrNull();
    return row == null
        ? null
        : jsonDecode(row.valueJson) as Map<String, dynamic>;
  }

  static Future<void> setting(
    AppDatabase db,
    String key,
    Map<String, dynamic> value,
  ) => db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: key,
          valueJson: jsonEncode(value),
          updatedAt: DateTime.now().toUtc(),
        ),
        mode: InsertMode.insertOrReplace,
      );
  Future<List<VaultClaim>> stores() async {
    final claims = await identity.claims();
    return [
      for (final id in claims.map((c) => c.companyId).toSet())
        DriveVaultIdentity.active(claims, id, accountId),
    ];
  }

  Future<VaultClaim> register(String recoveryKey) => VaultLock.run(() async {
    VaultCipher.parseKey(recoveryKey);
    final company = await db.select(db.companies).getSingle();
    final saved = await binding(db);
    if (saved != null && saved['accountId'] != accountId) {
      throw StateError(
        'Esta loja está associada a outra conta Google. Volte a ligar a conta original.',
      );
    }
    final claims = await identity.claims();
    final existing = claims.where((c) => c.companyId == company.id).toList();
    if (existing.isNotEmpty) {
      throw StateError(
        'Esta loja já existe no Drive. Use Reconectar ou Restaurar loja existente.',
      );
    }
    final claim = VaultClaim(
      id: const Uuid().v4(),
      companyId: company.id,
      companyName: company.tradeName,
      accountId: accountId,
      installationId: await identity.installationId(),
    );
    await secrets.write(
      'key.${claim.companyId}.$accountId',
      recoveryKey.trim(),
    );
    await identity.publish(claim);
    await store.create(
      'systock-v3-key-${claim.companyId}.bin',
      await VaultCipher.encrypt(
        utf8.encode(claim.companyId),
        recoveryKey,
        claim.companyId,
      ),
    );
    await _bind(claim);
    return claim;
  });
  Future<void> reconnect(
    VaultClaim claim, {
    String? recoveryKey,
  }) => VaultLock.run(() async {
    final company = await db.select(db.companies).getSingle();
    final saved = await binding(db);
    if (company.id != claim.companyId ||
        (saved != null && saved['accountId'] != accountId)) {
      throw StateError('A conta Google não corresponde à loja local.');
    }
    final active = DriveVaultIdentity.active(
      await identity.claims(),
      claim.companyId,
      accountId,
    );
    if (active.id != claim.id) {
      throw StateError(
        'A associação da loja mudou. Volte a selecionar a loja.',
      );
    }
    if (recoveryKey != null) {
      VaultCipher.parseKey(recoveryKey);
      final proof = await store.list('systock-v3-key-${claim.companyId}.bin');
      final history = proof.isNotEmpty ? proof : await backups(claim.companyId);
      if (history.isNotEmpty) {
        await VaultCipher.decrypt(
          await store.read(history.first.id),
          recoveryKey,
          claim.companyId,
        );
      } else {
        throw StateError(
          'Sincronize primeiro a loja no computador para validar a chave.',
        );
      }
      await secrets.write(
        'key.${claim.companyId}.$accountId',
        recoveryKey.trim(),
      );
    }
    if (await secrets.read('key.${claim.companyId}.$accountId') == null) {
      throw StateError('Introduza a chave de recuperação desta loja.');
    }
    await _bind(claim);
  });
  Future<void> _bind(VaultClaim claim) async {
    await db.transaction(() async {
      await setting(db, bindingSetting, {
        ...claim.toJson(),
        'email': email,
        'enabled': true,
        'mode': 'replica',
      });
    });
  }

  /// Join an empty installation without taking ownership away from the desktop.
  Future<void> join(VaultClaim claim, String recoveryKey) => VaultLock.run(
    () async {
      final local = await db.select(db.companies).get();
      if (local.isNotEmpty &&
          (local.length != 1 || local.single.id != claim.companyId)) {
        throw StateError('Este dispositivo já pertence a outra loja.');
      }
      final active = DriveVaultIdentity.active(
        await identity.claims(),
        claim.companyId,
        accountId,
      );
      if (active.id != claim.id) {
        throw StateError('Atualize a lista de lojas e tente novamente.');
      }
      VaultCipher.parseKey(recoveryKey);
      final proof = await store.list('systock-v3-key-${claim.companyId}.bin');
      final history = proof.isNotEmpty ? proof : await backups(claim.companyId);
      if (history.isEmpty) {
        throw StateError('Sincronize primeiro a loja no computador.');
      }
      await VaultCipher.decrypt(
        await store.read(history.first.id),
        recoveryKey,
        claim.companyId,
      );
      await secrets.write(
        'key.${claim.companyId}.$accountId',
        recoveryKey.trim(),
      );
      await _bind(claim);
    },
  );

  Future<void> disconnect() => VaultLock.run(() async {
    final saved = await binding(db);
    if (saved != null) {
      await setting(db, bindingSetting, {...saved, 'enabled': false});
    }
  });
  Future<List<VaultFile>> backups(String companyId, {String? claimId}) =>
      store.list(
        'systock-v2-backup-$companyId-${claimId == null ? '' : '$claimId-'}',
      );

  Future<void> _synchronizeLifetimeLicense(VaultClaim claim, String key) async {
    final prefix = 'systock-v3-license-${claim.companyId}-';
    final localCode = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('license.code'))).getSingleOrNull();
    final localCompany = await db.select(db.companies).getSingleOrNull();
    // Older sync versions changed the local device id. The signed lifetime
    // activation already stored with this shop remains valid for the shop.
    if (localCompany?.id == claim.companyId &&
        localCode != null &&
        LicenseService.validLifetimeCode(localCode.valueJson)) {
      final grant = {
        'companyId': claim.companyId,
        'accountId': accountId,
        'code': localCode.valueJson,
      };
      final bytes = utf8.encode(jsonEncode(grant));
      await store.create(
        '$prefix${sha256.convert(bytes)}.bin',
        await VaultCipher.encrypt(bytes, key, claim.companyId),
      );
      await setting(db, LicenseService.storeLicenseSetting, grant);
    }
    for (final file in await store.list(prefix)) {
      final grant = decodeVaultJson(
        await VaultCipher.decrypt(
          await store.read(file.id),
          key,
          claim.companyId,
        ),
      );
      if (grant['companyId'] != claim.companyId ||
          grant['accountId'] != accountId ||
          grant['code'] is! String ||
          !LicenseService.validLifetimeCode(grant['code'] as String)) {
        throw StateError('A licença do Google Drive não corresponde à loja.');
      }
      await setting(db, LicenseService.storeLicenseSetting, grant);
      return;
    }
  }

  Future<String> synchronize({bool force = false}) => VaultLock.run(() async {
    final saved = await binding(db);
    if (saved == null || saved['enabled'] != true) {
      throw StateError('Ligue esta loja ao Google Drive antes de sincronizar.');
    }
    if (saved['accountId'] != accountId) {
      throw StateError('A conta Google mudou. Volte a ligar a conta da loja.');
    }
    final claim = DriveVaultIdentity.active(
      await identity.claims(),
      saved['companyId'] as String,
      accountId,
    );
    final key = await secrets.read('key.${claim.companyId}.$accountId');
    if (key == null) {
      throw StateError(
        'Chave indisponível. Volte a ligar a conta com a chave de recuperação.',
      );
    }
    final local = await db.select(db.companies).get();
    if (local.length > 1 ||
        (local.isNotEmpty && local.single.id != claim.companyId)) {
      throw StateError(
        'A loja local não corresponde à associação Google Drive.',
      );
    }
    await _bind(claim);
    // Bridge the last encrypted backup so an already populated mobile receives
    // the desktop's data even when the old operation queue was marked synced.
    final history = await backups(claim.companyId, claimId: claim.id);
    if (history.isNotEmpty) {
      final latest = history.first;
      final marker = 'sync.replica.backup.${latest.id}';
      final imported = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals(marker))).getSingleOrNull();
      if (imported == null) {
        final clear = await VaultCipher.decrypt(
          await store.read(latest.id),
          key,
          claim.companyId,
        );
        final prepared = await VaultBackup(
          db,
          documents,
        ).prepareRestore(clear, claim.companyId);
        final snapshot = AppDatabase(NativeDatabase(prepared));
        try {
          await DriveReplicaSync(
            snapshot,
            store,
            companyId: claim.companyId,
            deviceId: 'backup-${claim.id}',
            key: key,
            documents: documents,
          ).publishInitial();
          await setting(db, marker, {'imported': true});
        } finally {
          await snapshot.close();
          await prepared.parent.delete(recursive: true);
        }
      }
    }
    await store.create(
      'systock-v3-key-${claim.companyId}.bin',
      await VaultCipher.encrypt(
        utf8.encode(claim.companyId),
        key,
        claim.companyId,
      ),
    );
    final result = await DriveReplicaSync(
      db,
      store,
      companyId: claim.companyId,
      deviceId: await identity.installationId(),
      key: key,
      documents: documents,
    ).synchronize();
    await _synchronizeLifetimeLicense(claim, key);
    final message = result.uploaded == 0 && result.received == 0
        ? 'Verificação concluída. Nenhuma alteração nova no dispositivo ou no Drive.'
        : 'Concluído: ${result.uploaded} alterações enviadas, ${result.received} recebidas.';
    await setting(db, 'sync.last_success', {
      'at': DateTime.now().toUtc().toIso8601String(),
      'summary': message,
      'uploaded': result.uploaded,
      'received': result.received,
      'conflicts': result.conflicts,
    });
    await (db.delete(
      db.appSettings,
    )..where((s) => s.key.equals('sync.last_failure'))).go();
    return result.conflicts == 0
        ? message
        : '$message ${result.conflicts} edições concorrentes; as duas versões foram guardadas nos conflitos.';
  });

  Future<void> restore(
    VaultClaim source,
    VaultFile backup,
    String recoveryKey,
  ) => VaultLock.run(() async {
    final currentClaim = DriveVaultIdentity.active(
      await identity.claims(),
      source.companyId,
      accountId,
    );
    if (source.id != currentClaim.id) {
      throw StateError('A caixa principal mudou. Atualize a lista de lojas.');
    }
    if (!(await backups(source.companyId)).any((f) => f.id == backup.id)) {
      throw StateError('O backup não pertence à loja selecionada.');
    }
    final local = await db.select(db.companies).getSingleOrNull();
    if (local != null && local.id != source.companyId) {
      final count = await db
          .customSelect(
            'SELECT (SELECT COUNT(*) FROM products) + (SELECT COUNT(*) FROM sales) + (SELECT COUNT(*) FROM purchases) + (SELECT COUNT(*) FROM inventory_movements) + (SELECT COUNT(*) FROM customers) + (SELECT COUNT(*) FROM suppliers) AS total',
          )
          .getSingle();
      if (count.read<int>('total') > 0) {
        throw StateError(
          'Já existem dados de outra loja neste dispositivo. Use uma instalação vazia para restaurar.',
        );
      }
    }
    final clear = await VaultCipher.decrypt(
      await store.read(backup.id),
      recoveryKey,
      source.companyId,
    );
    final prepared = await VaultBackup(
      db,
      documents,
    ).prepareRestore(clear, source.companyId);
    try {
      final claim = VaultClaim(
        id: const Uuid().v4(),
        companyId: source.companyId,
        companyName: source.companyName,
        accountId: accountId,
        installationId: await identity.installationId(),
        parent: source.id,
      );
      // Recheck after downloading. Any concurrent branch will fail closed.
      final recheck = DriveVaultIdentity.active(
        await identity.claims(),
        source.companyId,
        accountId,
      );
      if (recheck.id != source.id) {
        throw StateError('Outra transferência está em curso. Tente novamente.');
      }
      await secrets.write(
        'key.${claim.companyId}.$accountId',
        recoveryKey.trim(),
      );
      // Carry a validated snapshot into the new epoch before installing locally.
      await store.create(
        'systock-v2-backup-${claim.companyId}-${claim.id}-${const Uuid().v4()}.bin',
        await VaultCipher.encrypt(clear, recoveryKey, claim.companyId),
      );
      await identity.publish(claim);
      final staged = native.sqlite3.open(prepared.path);
      try {
        staged.execute(
          'INSERT OR REPLACE INTO app_settings(key,value_json,updated_at) VALUES(?,?,?)',
          [
            bindingSetting,
            jsonEncode({...claim.toJson(), 'email': email, 'enabled': true}),
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ],
        );
      } finally {
        staged.close();
      }
      final result = await BackupService(db).restore(
        backupPath: prepared.path,
        currentDatabasePath: '${documents.path}/stock_manager.sqlite',
        preRestoreBackupPath:
            '${documents.path}/backups/pre-drive-${const Uuid().v4()}.sqlite',
      );
      if (result case Failure(:final error)) {
        throw StateError(error.userMessage);
      }
    } finally {
      await prepared.parent.delete(recursive: true);
    }
  });
}
