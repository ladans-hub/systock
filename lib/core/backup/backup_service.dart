import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';

class BackupMetadata {
  const BackupMetadata({
    required this.path,
    required this.checksum,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.createdAt,
  });
  final String path, checksum;
  final int sizeBytes, schemaVersion;
  final DateTime createdAt;
  Map<String, Object> toJson() => {
    'path': path,
    'checksum': checksum,
    'sizeBytes': sizeBytes,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toIso8601String(),
  };
}

class RestoreMetadata {
  const RestoreMetadata(this.preRestoreBackupPath);
  final String preRestoreBackupPath;
}

class BackupService {
  const BackupService(this._db);
  final AppDatabase _db;
  Future<Result<BackupMetadata>> create(String destinationPath) async {
    try {
      final target = File(destinationPath);
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        await target.delete();
      }
      final escaped = destinationPath.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escaped'");
      final bytes = await target.readAsBytes();
      final metadata = BackupMetadata(
        path: destinationPath,
        checksum: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
        schemaVersion: _db.schemaVersion,
        createdAt: DateTime.now().toUtc(),
      );
      await File(
        '$destinationPath.json',
      ).writeAsString(jsonEncode(metadata.toJson()), flush: true);
      return Success(metadata);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível criar o backup.', cause: error),
      );
    }
  }

  Future<Result<void>> verify(String path, {String? expectedChecksum}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return const Failure(
          ValidationFailure('O arquivo de backup não existe.'),
        );
      }
      final bytes = await file.readAsBytes();
      if (expectedChecksum != null &&
          sha256.convert(bytes).toString() != expectedChecksum) {
        return const Failure(
          ValidationFailure('O backup está corrompido ou foi alterado.'),
        );
      }
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final rows = db.select('PRAGMA integrity_check');
        if (rows.single.values.single != 'ok') {
          return const Failure(
            ValidationFailure(
              'O backup não passou na verificação de integridade.',
            ),
          );
        }
      } finally {
        db.close();
      }
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível validar o backup.', cause: error),
      );
    }
  }

  Future<Result<RestoreMetadata>> restore({
    required String backupPath,
    required String currentDatabasePath,
    required String preRestoreBackupPath,
    String? expectedChecksum,
  }) async {
    final validation = await verify(
      backupPath,
      expectedChecksum: expectedChecksum,
    );
    if (validation is Failure<void>) return Failure(validation.error);
    final current = File(currentDatabasePath),
        safety = File(preRestoreBackupPath),
        temporary = File('$currentDatabasePath.restore');
    try {
      await safety.parent.create(recursive: true);
      if (await safety.exists()) {
        await safety.delete();
      }
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      await _db.close();
      await current.rename(safety.path);
      await File(backupPath).copy(temporary.path);
      await temporary.rename(current.path);
      final restored = sqlite3.open(current.path, mode: OpenMode.readOnly);
      try {
        if (restored.select('PRAGMA integrity_check').single.values.single !=
            'ok') {
          throw StateError('integrity_check failed after restore');
        }
      } finally {
        restored.close();
      }
      return Success(RestoreMetadata(safety.path));
    } catch (error) {
      try {
        if (await temporary.exists()) {
          await temporary.delete();
        }
        if (!await current.exists() && await safety.exists()) {
          await safety.copy(current.path);
        }
      } catch (_) {}
      return Failure(
        StorageFailure(
          'Não foi possível restaurar. O estado anterior foi preservado.',
          cause: error,
        ),
      );
    }
  }
}
