import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/sales/application/complete_sale.dart';
import 'package:systock/features/sales/application/sale_delivery_service.dart';

void main() {
  test('sales deliver immediately by default and can remain pending', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final companyId =
        (await SetupCompany(db)(
                  tradeName: 'Óptica',
                  adminName: 'Admin',
                  username: 'admin',
                )
                as Success<String>)
            .value;
    final company = await db.select(db.companies).getSingle();
    final warehouse = await db.select(db.warehouses).getSingle();
    final user = await db.select(db.users).getSingle();
    final now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'glasses',
            companyId: companyId,
            name: 'Óculos',
            trackStock: const Value(false),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );

    Future<String> sale(String number, {bool deliverNow = true}) async {
      final result = await CompleteSale(db)(
        companyId: companyId,
        warehouseId: warehouse.id,
        documentNumber: number,
        userId: user.id,
        deviceId: company.deviceId,
        deliverNow: deliverNow,
        lines: const [
          SaleLineInput(
            productId: 'glasses',
            description: 'Óculos',
            quantityMilli: 2000,
            unitPriceMinor: 10000,
            unitCostMinor: 4000,
          ),
        ],
        payments: const [PaymentInput('cash', 20000)],
      );
      return (result as Success<String>).value;
    }

    final deliveredSale = await sale('VEN-DELIVERED');
    var item = await (db.select(
      db.saleItems,
    )..where((row) => row.saleId.equals(deliveredSale))).getSingle();
    expect(item.deliveredQuantityMilli, 2000);
    expect(item.deliveredAt, isNotNull);

    final pendingSale = await sale('VEN-PENDING', deliverNow: false);
    item = await (db.select(
      db.saleItems,
    )..where((row) => row.saleId.equals(pendingSale))).getSingle();
    expect(item.deliveredQuantityMilli, 0);
    expect(item.deliveredAt, isNull);

    final service = SaleDeliveryService(db);
    expect(
      await service.deliver(item: item, quantityMilli: 1000),
      isA<Success<void>>(),
    );
    item = await (db.select(
      db.saleItems,
    )..where((row) => row.id.equals(item.id))).getSingle();
    expect(item.deliveredQuantityMilli, 1000);
    expect(item.deliveredAt, isNull);

    expect(await service.deliverAll([item]), isA<Success<void>>());
    item = await (db.select(
      db.saleItems,
    )..where((row) => row.id.equals(item.id))).getSingle();
    expect(item.deliveredQuantityMilli, 2000);
    expect(item.deliveredAt, isNotNull);
  });
}
