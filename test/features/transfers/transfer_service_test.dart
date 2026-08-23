import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/transfers/application/transfer_service.dart';

void main() {
  test('dispatch and receive record separate immutable movements', () async {
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
        source = await db.select(db.warehouses).getSingle(),
        now = DateTime.now().toUtc();
    await db
        .into(db.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: 'w2',
            companyId: company,
            name: 'Filial',
            code: 'FIL',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd',
          ),
        );
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
      warehouseId: source.id,
      quantityMilli: 5000,
      type: InventoryMovementType.initialStock,
      deviceId: 'd',
      userId: user,
      reason: 'Inicial',
    );
    final transfer =
        (await TransferService(db).create(
                  companyId: company,
                  sourceWarehouseId: source.id,
                  destinationWarehouseId: 'w2',
                  documentNumber: 'TRF-1',
                  userId: user,
                  deviceId: 'd',
                  lines: const [TransferLine('p', 2000)],
                )
                as Success<String>)
            .value;
    expect(
      await TransferService(db).dispatch(transfer, userId: user),
      isA<Success<void>>(),
    );
    expect(
      await TransferService(db).receive(transfer, userId: user),
      isA<Success<void>>(),
    );
    final balances = await db.select(db.inventoryBalances).get();
    expect(balances.map((b) => b.quantityMilli), containsAll([3000, 2000]));
    expect(await db.select(db.inventoryMovements).get(), hasLength(3));
  });
}
