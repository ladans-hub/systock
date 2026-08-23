import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  late AppDatabase db;
  late String company, user, warehouse;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final setup =
        await SetupCompany(db)(
              tradeName: 'Loja',
              adminName: 'Admin',
              username: 'admin',
            )
            as Success<String>;
    company = setup.value;
    user = (await db.select(db.users).getSingle()).id;
    warehouse = (await db.select(db.warehouses).getSingle()).id;
    final now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            companyId: company,
            name: 'Arroz',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
  });
  tearDown(() => db.close());
  test(
    'movement atomically writes ledger, balance, audit and outbox',
    () async {
      final result = await InventoryLedger(db).move(
        companyId: company,
        productId: 'p1',
        warehouseId: warehouse,
        quantityMilli: 10000,
        type: InventoryMovementType.initialStock,
        deviceId: 'd1',
        userId: user,
        reason: 'Carga inicial',
      );
      expect(result, isA<Success<int>>());
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        10000,
      );
      expect(await db.select(db.inventoryMovements).get(), hasLength(1));
      expect(await db.select(db.auditLogs).get(), hasLength(1));
      expect(await db.select(db.syncOperations).get(), hasLength(1));
    },
  );
  test('negative stock rejection leaves no partial records', () async {
    final result = await InventoryLedger(db).move(
      companyId: company,
      productId: 'p1',
      warehouseId: warehouse,
      quantityMilli: -1,
      type: InventoryMovementType.sale,
      deviceId: 'd1',
      userId: user,
      reason: 'Venda',
    );
    expect(result, isA<Failure<int>>());
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
    expect(await db.select(db.syncOperations).get(), isEmpty);
  });
}
