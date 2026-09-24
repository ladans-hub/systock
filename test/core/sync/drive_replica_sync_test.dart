import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/sync/drive_replica_sync.dart';
import 'package:systock/core/sync/drive_vault_store.dart';
import 'package:systock/core/sync/vault_cipher.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

class _MemoryStore implements DriveVaultStore {
  final values = <String, Uint8List>{};

  @override
  Future<List<VaultFile>> list(String prefix) async => [
    for (final entry in values.entries)
      if (entry.key.startsWith(prefix))
        VaultFile(entry.key, entry.key, DateTime.utc(2026, 9, 24)),
  ];

  @override
  Future<Uint8List> read(String id) async => values[id]!;

  @override
  Future<String> create(String name, List<int> bytes) async {
    values[name] = Uint8List.fromList(bytes);
    return name;
  }

  @override
  Future<void> delete(String id) async => values.remove(id);
}

void main() {
  test(
    'a stale device cannot remove sales received by another device',
    () async {
      final first = AppDatabase(NativeDatabase.memory());
      final second = AppDatabase(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp('replica-sales-');
      addTearDown(() async {
        await first.close();
        await second.close();
        await directory.delete(recursive: true);
      });

      final companyId =
          (await SetupCompany(first)(
                    tradeName: 'Loja',
                    adminName: 'Admin',
                    username: 'admin',
                  )
                  as Success<String>)
              .value;
      final company = await first.select(first.companies).getSingle();
      final store = _MemoryStore();
      final key = await VaultCipher.newRecoveryKey();
      final firstSync = DriveReplicaSync(
        first,
        store,
        companyId: companyId,
        deviceId: company.deviceId,
        key: key,
        documents: directory,
      );
      await firstSync.publishInitial();

      final secondSync = DriveReplicaSync(
        second,
        store,
        companyId: companyId,
        deviceId: 'second-device',
        key: key,
        documents: directory,
      );
      await secondSync.synchronize();

      await _insertSale(first, id: 'sale-first', totalMinor: 10000);
      await firstSync.synchronize();
      await _insertSale(second, id: 'sale-second', totalMinor: 25000);
      await secondSync.synchronize();
      await firstSync.synchronize();
      await secondSync.synchronize();
      await firstSync.synchronize();

      expect(await _saleTotal(first), 35000);
      expect(await _saleTotal(second), 35000);
      expect(await first.select(first.sales).get(), hasLength(2));
      expect(await second.select(second.sales).get(), hasLength(2));
    },
  );
}

Future<void> _insertSale(
  AppDatabase db, {
  required String id,
  required int totalMinor,
}) async {
  final company = await db.select(db.companies).getSingle();
  final warehouse = await db.select(db.warehouses).getSingle();
  final user = await db.select(db.users).getSingle();
  final now = DateTime.now().toUtc();
  await db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: id,
          companyId: company.id,
          warehouseId: warehouse.id,
          documentNumber: 'VEN-2026-$id',
          status: const Value('paid'),
          subtotalMinor: totalMinor,
          totalMinor: totalMinor,
          costMinor: 0,
          paidMinor: Value(totalMinor),
          createdBy: user.id,
          createdAt: now,
          updatedAt: now,
          deviceId: company.deviceId,
        ),
      );
}

Future<int> _saleTotal(AppDatabase db) async {
  final row = await db
      .customSelect(
        "SELECT COALESCE(SUM(total_minor), 0) AS total FROM sales WHERE status IN ('paid', 'completed')",
      )
      .getSingle();
  return row.read<int>('total');
}
