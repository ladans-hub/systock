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
    final current = File(currentDatabasePath);
    final safety = File(preRestoreBackupPath);
    File? temporary;
    var stage = 'preparar a cópia do backup';
    var originalMoved = false;
    var databaseClosed = false;
    try {
      // Stage and verify before closing the live database. This also avoids
      // depending on a removable drive during the replacement itself.
      final stagingDirectory = await current.parent.createTemp(
        '.systock-restore-',
      );
      temporary = File('${stagingDirectory.path}/database.sqlite');
      await File(backupPath).copy(temporary.path);
      final stagedValidation = await verify(
        temporary.path,
        expectedChecksum: expectedChecksum,
      );
      if (stagedValidation case Failure(:final error)) {
        return Failure(error);
      }

      stage = 'preparar a cópia de segurança do estado atual';
      await safety.parent.create(recursive: true);
      if (await FileSystemEntity.type(safety.path) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException(
          'O destino da cópia de segurança já existe.',
          safety.path,
        );
      }
      stage = 'concluir as escritas pendentes no banco';
      final checkpoint = await _db
          .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
          .getSingle();
      if (checkpoint.read<int>('busy') != 0) {
        throw StateError(
          'O banco está em uso. Feche as outras instâncias do Systock e tente novamente.',
        );
      }
      stage = 'fechar o banco atual';
      await _db.close();
      databaseClosed = true;
      stage = 'guardar o banco atual';
      await _renameWithRetry(current, safety.path);
      originalMoved = true;
      stage = 'instalar o backup';
      await _renameWithRetry(temporary, current.path);
      stage = 'verificar o banco restaurado';
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
      Object? rollbackError;
      if (originalMoved) {
        try {
          // Keep the safety copy even when the replacement needs rolling back.
          final rollback = File('${temporary!.parent.path}/rollback.sqlite');
          await safety.copy(rollback.path);
          await _renameWithRetry(rollback, current.path);
        } catch (failure) {
          rollbackError = failure;
        }
      }
      final preservation = rollbackError == null
          ? 'O estado anterior foi preservado.'
          : 'Não foi possível repor o estado anterior. A cópia de segurança está em: ${safety.path}.';
      return Failure(
        StorageFailure(
          'Não foi possível restaurar ao $stage. $preservation'
          '${databaseClosed ? " Reabra a aplicação antes de tentar novamente." : ""}',
          cause: rollbackError == null
              ? error
              : 'Erro original: $error\nErro ao repor o banco: $rollbackError',
        ),
      );
    } finally {
      final directory = temporary?.parent;
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // A leftover staging file must not turn a completed restore into a failure.
        }
      }
    }
  }

  Future<File> _renameWithRetry(File source, String destination) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await source.rename(destination);
      } on FileSystemException catch (error) {
        // Windows may briefly retain handles after the database is closed.
        final code = error.osError?.errorCode;
        if (!Platform.isWindows ||
            !const [5, 32, 33].contains(code) ||
            attempt >= 5) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
  }
}
