import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/sales/application/complete_sale.dart';
import 'package:systock/features/sales/application/return_sale.dart';

void main() {
  test(
    'partial return refunds and restocks without deleting the sale',
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
      final user = (await db.select(db.users).getSingle()).id,
          warehouse = (await db.select(db.warehouses).getSingle()).id;
      final now = DateTime.now().toUtc();
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: 'p',
              companyId: company,
              name: 'Item',
              saleMinor: const Value(1000),
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
      final saleId =
          (await CompleteSale(db)(
                    companyId: company,
                    warehouseId: warehouse,
                    documentNumber: 'VEN-1',
                    userId: user,
                    deviceId: 'd',
                    lines: const [
                      SaleLineInput(
                        productId: 'p',
                        description: 'Item',
                        quantityMilli: 2000,
                        unitPriceMinor: 1000,
                        unitCostMinor: 500,
                      ),
                    ],
                    payments: const [PaymentInput('cash', 2000)],
                  )
                  as Success<String>)
              .value;
      final item = await db.select(db.saleItems).getSingle();
      final result = await ReturnSale(db)(
        saleId: saleId,
        lines: [ReturnLineInput(item.id, 1000)],
        reason: 'Troca',
        userId: user,
        deviceId: 'd',
      );
      expect(result, isA<Success<String>>());
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        4000,
      );
      expect((await db.select(db.payments).get()).last.amountMinor, -1000);
      expect(
        (await db.select(db.sales).getSingle()).status,
        'partially_refunded',
      );
    },
  );
}
