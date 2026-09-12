import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/backup/backup_service.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/sync/google_drive_transport.dart';

enum InitialDriveRecovery { noRemoteSnapshot, localDataPresent, restored }

class DriveRecoverySnapshot {
  const DriveRecoverySnapshot(this.db, this.transport);
  final AppDatabase db;
  final GoogleDriveSyncTransport transport;

  Future<Result<void>> uploadLatest() async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final temporary = File(
        '${documents.path}/sync_snapshots/latest-recovery.sqlite',
      );
      final result = await BackupService(db).create(temporary.path);
      if (result case Failure<BackupMetadata>(:final error)) {
        return Failure(error);
      }
      final metadata = (result as Success<BackupMetadata>).value;
      await transport.uploadRecoverySnapshot(
        databaseBytes: await temporary.readAsBytes(),
        metadata: {
          ...metadata.toJson(),
          'appVersion': '1.0.0',
          'purpose': 'initial-device-recovery',
        },
      );
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível atualizar o snapshot de recuperação.',
          cause: error,
        ),
      );
    }
  }

  Future<Result<InitialDriveRecovery>> restoreIfLocalIsFresh() async {
    try {
      final localRecords = await _businessRecordCount();
      if (localRecords > 0) {
        return const Success(InitialDriveRecovery.localDataPresent);
      }
      final remote = await transport.downloadRecoverySnapshot().timeout(
        const Duration(minutes: 2),
      );
      if (remote == null) {
        return const Success(InitialDriveRecovery.noRemoteSnapshot);
      }
      final expectedChecksum = remote.metadata['checksum'] as String?;
      if (expectedChecksum == null ||
          sha256.convert(remote.bytes).toString() != expectedChecksum) {
        return const Failure(
          ValidationFailure('O snapshot do Google Drive está corrompido.'),
        );
      }
      final documents = await getApplicationDocumentsDirectory();
      final downloaded = File(
        '${documents.path}/sync_snapshots/downloaded-recovery.sqlite',
      );
      await downloaded.parent.create(recursive: true);
      await downloaded.writeAsBytes(remote.bytes, flush: true);
      final currentPath = '${documents.path}/stock_manager.sqlite';
      final safetyPath =
          '${documents.path}/backups/pre-drive-recovery-${DateTime.now().millisecondsSinceEpoch}.sqlite';
      final restored = await BackupService(db).restore(
        backupPath: downloaded.path,
        currentDatabasePath: currentPath,
        preRestoreBackupPath: safetyPath,
        expectedChecksum: expectedChecksum,
      );
      return switch (restored) {
        Success() => const Success(InitialDriveRecovery.restored),
        Failure(:final error) => Failure(error),
      };
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível recuperar os dados do Google Drive.',
          cause: error,
        ),
      );
    }
  }

  Future<int> _businessRecordCount() async {
    final row = await db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM products WHERE deleted_at IS NULL) +
        (SELECT COUNT(*) FROM sales WHERE deleted_at IS NULL) +
        (SELECT COUNT(*) FROM purchases WHERE deleted_at IS NULL) +
        (SELECT COUNT(*) FROM inventory_movements) AS total
    ''').getSingle();
    return row.read<int>('total');
  }
}
