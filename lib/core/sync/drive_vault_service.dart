import 'package:sqlite3/sqlite3.dart' as native;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
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
    await _bind(claim);
    return claim;
  });
  Future<void> reconnect(VaultClaim claim, {String? recoveryKey}) =>
      VaultLock.run(() async {
        final company = await db.select(db.companies).getSingle();
        final saved = await binding(db);
        if (company.id != claim.companyId ||
            (saved != null && saved['accountId'] != accountId)) {
          throw StateError('A conta Google não corresponde à loja local.');
        }
        await identity.assertWriter(claim);
        if (recoveryKey != null) {
          VaultCipher.parseKey(recoveryKey);
          final history = await backups(claim.companyId);
          if (history.isNotEmpty) {
            await VaultCipher.decrypt(
              await store.read(history.first.id),
              recoveryKey,
              claim.companyId,
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
  Future<void> _bind(VaultClaim claim) => setting(db, bindingSetting, {
    ...claim.toJson(),
    'email': email,
    'enabled': true,
  });
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

  Future<String> synchronize({bool force = false}) => VaultLock.run(() async {
    final saved = await binding(db);
    if (saved == null || saved['enabled'] != true) {
      throw StateError('Ligue esta loja ao Google Drive antes de sincronizar.');
    }
    if (saved['accountId'] != accountId) {
      throw StateError(
        'A conta Google mudou. O envio foi bloqueado para proteger os dados.',
      );
    }
    final claim = VaultClaim.fromJson(saved);
    final company = await (db.select(
      db.companies,
    )..where((row) => row.id.equals(claim.companyId))).getSingleOrNull();
    if (company == null) {
      throw StateError(
        'A loja local não corresponde à associação Google Drive.',
      );
    }
    await identity.assertWriter(claim);
    final key = await secrets.read('key.${claim.companyId}.$accountId');
    if (key == null) {
      throw StateError(
        'Chave indisponível. Volte a ligar a conta com a chave de recuperação.',
      );
    }
    final backup = await VaultBackup(
      db,
      documents,
    ).capture(companyId: claim.companyId);
    final previous = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('sync.last_success'))).getSingleOrNull();
    final last = previous == null
        ? null
        : jsonDecode(previous.valueJson) as Map<String, dynamic>;
    if (!force &&
        last?['fingerprint'] == backup.fingerprint &&
        last?['claimId'] == claim.id &&
        (await backups(claim.companyId, claimId: claim.id)).isNotEmpty) {
      return 'Os dados já estão atualizados no Drive.';
    }
    final encrypted = await VaultCipher.encrypt(
      backup.bytes,
      key,
      claim.companyId,
    );
    await identity.assertWriter(claim);
    final id = await store.create(
      'systock-v2-backup-${claim.companyId}-${claim.id}-${const Uuid().v4()}.bin',
      encrypted,
    );
    // Downloads authenticate the uploaded data before acknowledging local changes.
    await VaultCipher.decrypt(await store.read(id), key, claim.companyId);
    await identity.assertWriter(claim);
    await db.transaction(() async {
      for (var offset = 0; offset < backup.operations.length; offset += 400) {
        final end = offset + 400 < backup.operations.length
            ? offset + 400
            : backup.operations.length;
        await (db.update(db.syncOperations)..where(
              (o) => o.operationId.isIn(backup.operations.sublist(offset, end)),
            ))
            .write(const SyncOperationsCompanion(status: Value('synced')));
      }
      await setting(db, 'sync.last_success', {
        'at': DateTime.now().toUtc().toIso8601String(),
        'fingerprint': backup.fingerprint,
        'claimId': claim.id,
        'backupId': id,
      });
      await (db.delete(
        db.appSettings,
      )..where((s) => s.key.equals('sync.last_failure'))).go();
    });
    // Retention applies only to this writer's own versions, never another epoch.
    final history = await backups(claim.companyId, claimId: claim.id);
    for (final old in history.skip(30)) {
      if (old.id == id) continue;
      await identity.assertWriter(claim);
      try {
        await store.delete(old.id);
      } catch (_) {
        /* Retry retention on next backup. */
      }
    }
    return 'Cópia cifrada guardada no Google Drive.';
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
