import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/sync/initial_sync_snapshot.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test(
    'connecting accepts multiple operations for an existing product',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final company =
          (await SetupCompany(db)(
                    tradeName: 'Loja',
                    adminName: 'Admin',
                    username: 'admin',
                  )
                  as Success<String>)
              .value;
      final now = DateTime.now().toUtc();
      for (final id in ['edited', 'untracked']) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: id,
                companyId: company,
                name: id,
                createdAt: now,
                updatedAt: now,
                deviceId: 'desktop',
              ),
            );
      }
      for (var version = 1; version <= 2; version++) {
        await db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: 'edit-$version',
                entityType: 'product',
                entityId: 'edited',
                operation: version == 1 ? 'CREATE' : 'UPDATE',
                deviceId: 'desktop',
                payloadJson: '{}',
                createdAt: now,
                version: version,
                checksum: '',
              ),
            );
      }

      expect(await InitialSyncSnapshot(db).enqueue(), 1);
      final operations = await db.select(db.syncOperations).get();
      expect(operations.where((o) => o.entityId == 'edited'), hasLength(2));
      expect(operations.where((o) => o.entityId == 'untracked'), hasLength(1));
      expect(await InitialSyncSnapshot(db).enqueue(), 0);
      expect(await db.select(db.syncOperations).get(), hasLength(3));
    },
  );
}
