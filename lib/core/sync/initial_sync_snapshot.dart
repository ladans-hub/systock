import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

class InitialSyncSnapshot {
  const InitialSyncSnapshot(this.db);
  final AppDatabase db;

  Future<int> enqueue() async {
    final done = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('sync.initial_snapshot'))).getSingleOrNull();
    if (done != null) return 0;
    final products = await (db.select(
      db.products,
    )..where((p) => p.deletedAt.isNull())).get();
    var count = 0;
    await db.transaction(() async {
      for (final product in products) {
        final exists =
            await (db.select(db.syncOperations)..where(
                  (o) =>
                      o.entityType.equals('product') &
                      o.entityId.equals(product.id),
                ))
                .getSingleOrNull();
        if (exists != null) continue;
        final barcode =
            await (db.select(db.productBarcodes)
                  ..where((b) => b.productId.equals(product.id))
                  ..limit(1))
                .getSingleOrNull();
        final payload = jsonEncode({
          'companyId': product.companyId,
          'name': product.name,
          'sku': product.sku,
          'barcode': barcode?.barcode,
          'costMinor': product.costMinor,
          'saleMinor': product.saleMinor,
          'createdAt': product.createdAt.toIso8601String(),
          'updatedAt': product.updatedAt.toIso8601String(),
        });
        await db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: const Uuid().v7(),
                entityType: 'product',
                entityId: product.id,
                operation: 'CREATE',
                deviceId: product.deviceId,
                payloadJson: payload,
                createdAt: DateTime.now().toUtc(),
                version: product.version,
                checksum: sha256.convert(utf8.encode(payload)).toString(),
              ),
            );
        count++;
      }
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'sync.initial_snapshot',
              valueJson: jsonEncode({
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'entities': count,
              }),
              updatedAt: DateTime.now().toUtc(),
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
    return count;
  }
}
