import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/backup/backup_service.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class AutomaticBackupScheduler {
  const AutomaticBackupScheduler(this.db, {this.retention = 10});
  final AppDatabase db;
  final int retention;

  Future<void> runIfDue() async {
    try {
      final company = await db.select(db.companies).getSingleOrNull();
      if (company == null) return;
      final last =
          await (db.select(db.backups)
                ..where((b) => b.status.equals('valid'))
                ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (last != null &&
          DateTime.now().toUtc().difference(last.createdAt) <
              const Duration(hours: 24)) {
        return;
      }
      final docs = await getApplicationDocumentsDirectory(),
          now = DateTime.now().toUtc();
      final path =
          '${docs.path}/systock_backups/automatic-${now.toIso8601String().replaceAll(':', '-')}.sqlite';
      final result = await BackupService(db).create(path);
      if (result case Success(:final value)) {
        await db
            .into(db.backups)
            .insert(
              BackupsCompanion.insert(
                id: const Uuid().v7(),
                path: value.path,
                checksum: value.checksum,
                schemaVersion: value.schemaVersion,
                sizeBytes: value.sizeBytes,
                deviceId: company.deviceId,
                createdAt: value.createdAt,
                status: 'valid',
              ),
            );
        await prune();
      }
    } catch (_) {
      // Automatic backup is retried at the next startup.
    }
  }

  Future<void> prune() async {
    if (retention <= 0) return;
    final obsolete =
        await (db.select(db.backups)
              ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])
              ..limit(-1, offset: retention))
            .get();
    for (final backup in obsolete) {
      final file = File(backup.path), metadata = File('${backup.path}.json');
      if (await file.exists()) await file.delete();
      if (await metadata.exists()) await metadata.delete();
      await (db.delete(db.backups)..where((b) => b.id.equals(backup.id))).go();
    }
  }
}
