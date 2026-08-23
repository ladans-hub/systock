import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/sales/application/complete_sale.dart';

void main() {
  test('sale, split payments and stock movement commit atomically', () async {
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
    final user = (await db.select(db.users).getSingle()).id,
        warehouse = (await db.select(db.warehouses).getSingle()).id;
    final now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            companyId: company,
            name: 'Arroz',
            saleMinor: const Value(10000),
            costMinor: const Value(6000),
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await InventoryLedger(db).move(
      companyId: company,
      productId: 'p1',
      warehouseId: warehouse,
      quantityMilli: 5000,
      type: InventoryMovementType.initialStock,
      deviceId: 'd1',
      userId: user,
      reason: 'Inicial',
    );
    final result = await CompleteSale(db)(
      companyId: company,
      warehouseId: warehouse,
      documentNumber: 'VEN-2026-000001',
      userId: user,
      deviceId: 'd1',
      lines: const [
        SaleLineInput(
          productId: 'p1',
          description: 'Arroz',
          quantityMilli: 2000,
          unitPriceMinor: 10000,
          unitCostMinor: 6000,
        ),
      ],
      payments: const [
        PaymentInput('cash', 5000),
        PaymentInput('mpesa', 15000),
      ],
    );
    expect(result, isA<Success<String>>());
    expect(
      (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
      3000,
    );
    expect(await db.select(db.payments).get(), hasLength(2));
    expect((await db.select(db.sales).getSingle()).costMinor, 12000);
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'customer',
            companyId: company,
            name: 'Cliente Crédito',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    final creditResult = await CompleteSale(db)(
      companyId: company,
      warehouseId: warehouse,
      documentNumber: 'VEN-2026-000002',
      userId: user,
      deviceId: 'd1',
      customerId: 'customer',
      lines: const [
        SaleLineInput(
          productId: 'p1',
          description: 'Arroz',
          quantityMilli: 1000,
          unitPriceMinor: 10000,
          unitCostMinor: 6000,
        ),
      ],
      payments: const [PaymentInput('credit', 10000)],
    );
    expect(creditResult, isA<Success<String>>());
    expect(
      (await (db.select(
        db.customers,
      )..where((c) => c.id.equals('customer'))).getSingle()).balanceMinor,
      10000,
    );
    expect(await db.select(db.customerAccountMovements).get(), hasLength(1));
  });
  test('insufficient stock rolls back sale and payments', () async {
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
    final user = (await db.select(db.users).getSingle()).id,
        warehouse = (await db.select(db.warehouses).getSingle()).id;
    final now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            companyId: company,
            name: 'Item',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    final result = await CompleteSale(db)(
      companyId: company,
      warehouseId: warehouse,
      documentNumber: 'VEN-1',
      userId: user,
      deviceId: 'd1',
      lines: const [
        SaleLineInput(
          productId: 'p1',
          description: 'Item',
          quantityMilli: 1000,
          unitPriceMinor: 100,
          unitCostMinor: 50,
        ),
      ],
      payments: const [PaymentInput('cash', 100)],
    );
    expect(result, isA<Failure<String>>());
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.payments).get(), isEmpty);
  });
}
