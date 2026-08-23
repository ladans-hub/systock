import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/sales/application/complete_sale.dart';
import 'package:systock/features/sales/application/reverse_sale.dart';

void main() {
  test(
    'cancellation preserves original and compensates stock and payments',
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
                  .value,
          user = (await db.select(db.users).getSingle()).id,
          warehouse = (await db.select(db.warehouses).getSingle()).id;
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
              deviceId: 'd',
            ),
          );
      await InventoryLedger(db).move(
        companyId: company,
        productId: 'p',
        warehouseId: warehouse,
        quantityMilli: 3000,
        type: InventoryMovementType.initialStock,
        deviceId: 'd',
        userId: user,
        reason: 'Inicial',
      );
      final sold =
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
                        quantityMilli: 1000,
                        unitPriceMinor: 1000,
                        unitCostMinor: 500,
                      ),
                    ],
                    payments: const [PaymentInput('cash', 1000)],
                  )
                  as Success<String>)
              .value;
      final reversed = await ReverseSale(db)(
        saleId: sold,
        documentNumber: 'DEV-1',
        userId: user,
        deviceId: 'd',
        reason: 'Cliente devolveu',
      );
      expect(reversed, isA<Success<String>>());
      expect(await db.select(db.sales).get(), hasLength(2));
      expect(
        (await (db.select(
          db.sales,
        )..where((s) => s.id.equals(sold))).getSingle()).status,
        'cancelled',
      );
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        3000,
      );
      expect(await db.select(db.payments).get(), hasLength(2));
    },
  );
}
