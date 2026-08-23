import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/sync/sync_engine.dart';
import 'package:systock/core/sync/sync_transport.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test('remote inventory event is idempotent and rebuilds balance', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final company =
        (await SetupCompany(db)(
                  tradeName: 'B',
                  adminName: 'Admin',
                  username: 'admin',
                )
                as Success<String>)
            .value;
    final warehouse = (await db.select(db.warehouses).getSingle()).id,
        user = (await db.select(db.users).getSingle()).id;
    final now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p',
            companyId: company,
            name: 'Item',
            createdAt: now,
            updatedAt: now,
            deviceId: 'b',
          ),
        );
    final payload = jsonEncode({
      'id': 'm-remote',
      'companyId': company,
      'productId': 'p',
      'warehouseId': warehouse,
      'quantityMilli': 2000,
      'type': 'sale',
      'deviceId': 'a',
      'userId': user,
      'reason': 'offline',
      'createdAt': now.toIso8601String(),
    });
    final envelope = SyncEnvelope(
      operationId: 'op-1',
      deviceId: 'a',
      entityType: 'inventory_movement',
      entityId: 'm-remote',
      operation: 'CREATE',
      version: 1,
      payloadJson: payload,
      checksum: sha256.convert(utf8.encode(payload)).toString(),
      createdAt: now,
    );
    final transport = InMemorySyncTransport();
    await transport.upload([envelope]);
    final first =
        await SyncEngine(db, transport).synchronize() as Success<SyncSummary>;
    expect(first.value.applied, 1);
    expect(
      (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
      2000,
    );
    final second =
        await SyncEngine(db, transport).synchronize() as Success<SyncSummary>;
    expect(second.value.applied, 0);
    expect(await db.select(db.inventoryMovements).get(), hasLength(1));
  });
}
