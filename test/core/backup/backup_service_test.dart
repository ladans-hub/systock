import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/backup/backup_service.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test(
    'creates portable backup with checksum and verifies SQLite integrity',
    () async {
      final dir = await Directory.systemTemp.createTemp('systock-backup-');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase(File('${dir.path}/source.sqlite')));
      addTearDown(db.close);
      await SetupCompany(db)(
        tradeName: 'Loja',
        adminName: 'Admin',
        username: 'admin',
      );
      final result = await BackupService(
        db,
      ).create('${dir.path}/backup.sqlite');
      expect(result, isA<Success<BackupMetadata>>());
      final metadata = (result as Success<BackupMetadata>).value;
      expect(await File('${metadata.path}.json').exists(), isTrue);
      expect(
        await BackupService(
          db,
        ).verify(metadata.path, expectedChecksum: metadata.checksum),
        isA<Success<void>>(),
      );
    },
  );
  test('rejects a backup with mismatched checksum', () async {
    final dir = await Directory.systemTemp.createTemp('systock-checksum-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/bad.sqlite');
    await file.writeAsString('not sqlite');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final result = await BackupService(
      db,
    ).verify(file.path, expectedChecksum: 'wrong');
    expect(result, isA<Failure<void>>());
  });
  test(
    'restore preserves pre-restore database and replaces atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp('systock-restore-');
      addTearDown(() => dir.delete(recursive: true));
      final sourcePath = '${dir.path}/current.sqlite',
          backupPath = '${dir.path}/backup.sqlite',
          safetyPath = '${dir.path}/before.sqlite';
      final db = AppDatabase(NativeDatabase(File(sourcePath)));
      await SetupCompany(db)(
        tradeName: 'Original',
        adminName: 'Admin',
        username: 'admin',
      );
      final metadata =
          (await BackupService(db).create(backupPath)
                  as Success<BackupMetadata>)
              .value;
      final company = await db.select(db.companies).getSingle();
      await (db.update(db.companies)..where((c) => c.id.equals(company.id)))
          .write(const CompaniesCompanion(tradeName: Value('Alterada')));
      final restored = await BackupService(db).restore(
        backupPath: backupPath,
        currentDatabasePath: sourcePath,
        preRestoreBackupPath: safetyPath,
        expectedChecksum: metadata.checksum,
      );
      expect(
        restored,
        isA<Success<RestoreMetadata>>(),
        reason: restored is Failure<RestoreMetadata>
            ? "${restored.error.userMessage} ${restored.error.cause}"
            : null,
      );
      expect(await File(safetyPath).exists(), isTrue);
      final reopened = AppDatabase(NativeDatabase(File(sourcePath)));
      addTearDown(reopened.close);
      expect(
        (await reopened.select(reopened.companies).getSingle()).tradeName,
        'Original',
      );
    },
  );
  test(
    'existing safety destination is preserved and the live database remains usable',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'systock-restore-failure-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(
        NativeDatabase(File('${dir.path}/current.sqlite')),
      );
      addTearDown(db.close);
      await SetupCompany(db)(
        tradeName: 'Original',
        adminName: 'Admin',
        username: 'admin',
      );
      final service = BackupService(db);
      await service.create('${dir.path}/backup.sqlite');
      final safety = File('${dir.path}/before.sqlite');
      await safety.writeAsString('existing safety backup');
      final result = await service.restore(
        backupPath: '${dir.path}/backup.sqlite',
        currentDatabasePath: '${dir.path}/current.sqlite',
        preRestoreBackupPath: safety.path,
      );
      expect(result, isA<Failure<RestoreMetadata>>());
      final error = (result as Failure<RestoreMetadata>).error;
      expect(error.userMessage, contains('preparar a cópia de segurança'));
      expect(error.cause, isA<FileSystemException>());
      expect(await safety.readAsString(), 'existing safety backup');
      expect((await db.select(db.companies).getSingle()).tradeName, 'Original');
      expect(
        await dir.list().where((entry) => entry is Directory).toList(),
        isEmpty,
      );
    },
  );
}
