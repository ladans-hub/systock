import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:systock/core/backup/backup_service.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class VaultBackup {
  const VaultBackup(this.db, this.documents);
  final AppDatabase db;
  final Directory documents;

  Future<({List<int> bytes, String fingerprint, List<String> operations})>
  capture({String? companyId}) async {
    final temp = await Directory.systemTemp.createTemp('systock-vault-');
    try {
      final path = '${temp.path}/store.sqlite';
      final result = await BackupService(db).create(path);
      if (result case Failure(:final error)) {
        throw StateError(error.userMessage);
      }
      final copy = sqlite3.open(path);
      final images = <String, String>{};
      late List<String> operations;
      try {
        operations = copy
            .select(
              "SELECT operation_id FROM sync_operations WHERE status='pending'",
            )
            .map((r) => r['operation_id'] as String)
            .toList();
        for (final table in ['products', 'companies']) {
          final column = table == 'products' ? 'image_path' : 'logo_path';
          for (final row in copy.select(
            'SELECT id, $column FROM $table WHERE $column IS NOT NULL',
          )) {
            final original = row[column] as String;
            final file = File(original);
            if (!await file.exists()) {
              copy.execute('UPDATE $table SET $column=NULL WHERE id=?', [
                row['id'],
              ]);
              continue;
            }
            final bytes = await file.readAsBytes();
            final extension = original.split('.').last.toLowerCase();
            final safeExtension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)
                ? extension
                : 'img';
            final name = '${sha256.convert(bytes)}.$safeExtension';
            images[name] = base64Encode(bytes);
            copy.execute('UPDATE $table SET $column=? WHERE id=?', [
              'vault-assets/$name',
              row['id'],
            ]);
          }
        }
        // Account bindings and session identity are local, never restored blindly.
        copy.execute(
          "DELETE FROM app_settings WHERE key LIKE 'sync.%' OR key = 'session.current_user'",
        );
        copy.execute("UPDATE sync_operations SET status='synced'");
        copy.execute('DELETE FROM backups');
        copy.execute('VACUUM');
        final companyRows = companyId == null
            ? copy.select('SELECT id FROM companies')
            : copy.select('SELECT id FROM companies WHERE id = ?', [companyId]);
        if (companyRows.length != 1) {
          throw StateError(
            companyId == null
                ? 'Não foi possível identificar a loja local no backup.'
                : 'A loja local não corresponde à associação Google Drive.',
          );
        }
        final company = companyRows.single['id'] as String;
        final sqliteBytes = await File(path).readAsBytes();
        final payload = {
          'schema': db.schemaVersion,
          'companyId': company,
          'database': base64Encode(sqliteBytes),
          'checksum': sha256.convert(sqliteBytes).toString(),
          'images': images,
        };
        final bytes = gzip.encode(utf8.encode(jsonEncode(payload)));
        // Hash logical rows rather than SQLite header counters modified by VACUUM.
        final tables = copy.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );
        final logical = {
          for (final t in tables)
            t['name'] as String: copy
                .select('SELECT * FROM "${t['name']}" ORDER BY rowid')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
        };
        final fingerprint = sha256
            .convert(
              utf8.encode(jsonEncode({'data': logical, 'images': images})),
            )
            .toString();
        return (bytes: bytes, fingerprint: fingerprint, operations: operations);
      } finally {
        copy.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<File> prepareRestore(List<int> bytes, String companyId) async {
    final payload =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    final schema = payload['schema'] as int;
    if (schema > db.schemaVersion ||
        schema < 1 ||
        payload['companyId'] != companyId) {
      throw StateError(
        'O backup pertence a outra loja ou exige uma versão mais recente do Systock.',
      );
    }
    final database = base64Decode(payload['database'] as String);
    if (sha256.convert(database).toString() != payload['checksum']) {
      throw StateError('O backup está corrompido.');
    }
    final temp = await Directory.systemTemp.createTemp(
      'systock-restore-drive-',
    );
    final target = File('${temp.path}/store.sqlite');
    try {
      await target.writeAsBytes(database, flush: true);
      final verified = await BackupService(
        db,
      ).verify(target.path, expectedChecksum: payload['checksum'] as String);
      if (verified case Failure(:final error)) {
        throw StateError(error.userMessage);
      }
      final restored = sqlite3.open(target.path);
      try {
        if (restored.select('PRAGMA user_version').single.values.single !=
                schema ||
            restored.select('SELECT id FROM companies').single['id'] !=
                companyId) {
          throw StateError('Identidade do backup inválida.');
        }
        final assetDir = Directory(
          '${documents.path}/recovered-assets/${const Uuid().v4()}',
        );
        final images = payload['images'] as Map<String, dynamic>;
        if (images.isNotEmpty) await assetDir.create(recursive: true);
        for (final entry in images.entries) {
          if (!RegExp(r'^[a-f0-9]{64}\.[a-z0-9]{1,8}$').hasMatch(entry.key)) {
            throw StateError('Nome de imagem inválido no backup.');
          }
          final imageBytes = base64Decode(entry.value as String);
          if (!entry.key.startsWith(sha256.convert(imageBytes).toString())) {
            throw StateError('Imagem corrompida.');
          }
          final image = File('${assetDir.path}/${entry.key}');
          await image.writeAsBytes(imageBytes, flush: true);
          for (final table in ['products', 'companies']) {
            final column = table == 'products' ? 'image_path' : 'logo_path';
            restored.execute('UPDATE $table SET $column=? WHERE $column=?', [
              image.path,
              'vault-assets/${entry.key}',
            ]);
          }
        }
        restored.execute(
          "DELETE FROM app_settings WHERE key LIKE 'sync.%' OR key='session.current_user'",
        );
      } finally {
        restored.close();
      }
      return target;
    } catch (_) {
      await temp.delete(recursive: true);
      rethrow;
    }
  }
}
