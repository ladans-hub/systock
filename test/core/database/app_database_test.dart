import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';

void main() {
  late AppDatabase database;
  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('foreign keys reject orphan products', () async {
    await expectLater(
      database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              id: 'p1',
              companyId: 'missing',
              name: 'Produto',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              deviceId: 'device-a',
            ),
          ),
      throwsA(anything),
    );
  });

  test('inventory cache can be rebuilt from immutable movements', () async {
    final now = DateTime.utc(2026);
    await database
        .into(database.companies)
        .insert(
          CompaniesCompanion.insert(
            id: 'c1',
            tradeName: 'Loja',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await database
        .into(database.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: 'w1',
            companyId: 'c1',
            name: 'Principal',
            code: 'MAIN',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            companyId: 'c1',
            name: 'Arroz',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await database
        .into(database.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: 'm1',
            companyId: 'c1',
            productId: 'p1',
            warehouseId: 'w1',
            movementType: 'INITIAL_STOCK',
            quantityMilli: 5000,
            balanceBeforeMilli: 0,
            balanceAfterMilli: 5000,
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await database.rebuildInventoryBalances();
    expect(
      (await database.select(database.inventoryBalances).getSingle())
          .quantityMilli,
      5000,
    );
  });
}
