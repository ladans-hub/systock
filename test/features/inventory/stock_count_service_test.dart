import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/inventory/application/stock_count_service.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test('approved physical count creates only divergence movement', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final company =
            (await SetupCompany(db)(
                      tradeName: 'Loja',
                      adminName: 'Admin',
                      username: 'admin',
                    )
                    as Success<String>)
                .value,
        user = (await db.select(db.users).getSingle()).id,
        warehouse = (await db.select(db.warehouses).getSingle()).id,
        now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p',
            companyId: company,
            name: 'Item',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd',
          ),
        );
    await InventoryLedger(db).move(
      companyId: company,
      productId: 'p',
      warehouseId: warehouse,
      quantityMilli: 5000,
      type: InventoryMovementType.initialStock,
      deviceId: 'd',
      userId: user,
      reason: 'Inicial',
    );
    final service = StockCountService(db),
        count =
            (await service.create(
                      companyId: company,
                      warehouseId: warehouse,
                      documentNumber: 'INV-1',
                      userId: user,
                      deviceId: 'd',
                    )
                    as Success<String>)
                .value,
        item = await db.select(db.stockCountItems).getSingle();
    await service.count(item.id, 4000);
    expect(await service.approve(count, userId: user), isA<Success<void>>());
    expect(
      (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
      4000,
    );
    expect(await db.select(db.inventoryMovements).get(), hasLength(2));
  });
}
