import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/purchases/application/receive_purchase.dart';

void main() {
  test(
    'receiving a purchase creates items and increases stock transactionally',
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
      final user = (await db.select(db.users).getSingle()).id;
      final warehouse = (await db.select(db.warehouses).getSingle()).id;
      final now = DateTime.now().toUtc();
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: 's1',
              companyId: company,
              name: 'Fornecedor',
              createdAt: now,
              updatedAt: now,
              deviceId: 'd1',
            ),
          );
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
      final result = await ReceivePurchase(db)(
        companyId: company,
        supplierId: 's1',
        warehouseId: warehouse,
        documentNumber: 'COM-2026-000001',
        userId: user,
        deviceId: 'd1',
        lines: const [
          PurchaseLineInput(
            productId: 'p1',
            quantityMilli: 2000,
            unitCostMinor: 5000,
          ),
        ],
        paidMinor: 10000,
      );
      expect(result, isA<Success<String>>());
      expect((await db.select(db.purchases).getSingle()).totalMinor, 10000);
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        2000,
      );
      expect((await db.select(db.products).getSingle()).costMinor, 5000);
    },
  );
}
