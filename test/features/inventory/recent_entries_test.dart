import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/features/inventory/presentation/recent_entries_page.dart';

void main() {
  test(
    'recent entries exclude exits and total current stock across warehouses',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 9, 20);
      await db
          .into(db.companies)
          .insert(
            CompaniesCompanion.insert(
              id: 'c',
              tradeName: 'Loja',
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
              companyId: 'c',
              name: 'Arroz',
              createdAt: now,
              updatedAt: now,
              deviceId: 'd',
            ),
          );
      for (final warehouse in ['w1', 'w2']) {
        await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                id: warehouse,
                companyId: 'c',
                name: warehouse,
                code: warehouse,
                createdAt: now,
                updatedAt: now,
                deviceId: 'd',
              ),
            );
        await db
            .into(db.inventoryBalances)
            .insert(
              InventoryBalancesCompanion.insert(
                productId: 'p',
                warehouseId: warehouse,
                quantityMilli: const Value(3500),
                updatedAt: now,
              ),
            );
      }
      for (var i = 0; i < 2; i++) {
        await db
            .into(db.productBarcodes)
            .insert(
              ProductBarcodesCompanion.insert(
                id: 'barcode$i',
                productId: 'p',
                barcode: '1234$i',
                primaryBarcode: Value(i == 1),
                createdAt: now,
                updatedAt: now,
                deviceId: 'd',
              ),
            );
      }
      for (var i = 0; i < 3; i++) {
        final quantity = i == 2 ? -1000 : 4000;
        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: 'm$i',
                companyId: 'c',
                productId: 'p',
                warehouseId: 'w1',
                movementType: i == 2 ? 'sale' : 'purchase',
                quantityMilli: quantity,
                balanceBeforeMilli: 0,
                balanceAfterMilli: quantity,
                createdAt: now.add(Duration(minutes: i)),
                updatedAt: now,
                deviceId: 'd',
              ),
            );
      }
      final entries = await watchRecentEntries(db, 'c').first;
      expect(entries, hasLength(2));
      expect(
        entries.first.createdAt.toUtc(),
        now.add(const Duration(minutes: 1)),
      );
      expect(entries.first.barcode, '12341');
      expect(entries.first.product, 'Arroz');
      expect(entries.first.quantityMilli, 4000);
      expect(entries.first.stockMilli, 7000);
      expect(await watchRecentEntries(db, 'other').first, isEmpty);
      await db
          .update(db.inventoryBalances)
          .write(const InventoryBalancesCompanion(quantityMilli: Value(1000)));
      expect((await watchRecentEntries(db, 'c').first).first.stockMilli, 2000);
    },
  );
}
