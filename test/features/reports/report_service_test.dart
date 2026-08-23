import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/features/sales/application/complete_sale.dart';

void main() {
  test('calculates financial KPIs and exports stock CSV', () async {
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
            name: 'Arroz',
            costMinor: const Value(6000),
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
    await CompleteSale(db)(
      companyId: company,
      warehouseId: warehouse,
      documentNumber: 'VEN-1',
      userId: user,
      deviceId: 'd',
      lines: const [
        SaleLineInput(
          productId: 'p',
          description: 'Arroz',
          quantityMilli: 1000,
          unitPriceMinor: 10000,
          unitCostMinor: 6000,
        ),
      ],
      payments: const [PaymentInput('cash', 10000)],
    );
    final service = ReportService(db);
    final kpi = await service.salesKpis(
      company,
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    );
    expect(kpi.grossProfitMinor, 4000);
    expect(kpi.margin, .4);
    final ranking = await service.productRanking(
      company,
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    );
    expect(ranking.single.name, 'Arroz');
    expect(ranking.single.quantityMilli, 1000);
    final series = await service.revenueSeries(
      company,
      now.subtract(const Duration(days: 90)),
      now.add(const Duration(days: 1)),
    );
    expect(series.values.length, lessThanOrEqualTo(24));
    expect(series.values.reduce((a, b) => a + b), 10000);
    final filtered = await service.sales(
      company,
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    );
    expect(filtered.single.documentNumber, 'VEN-1');
    final salesCsv = service.salesCsv(
      filtered,
      from: now.subtract(const Duration(days: 1)),
      to: now.add(const Duration(days: 1)),
    );
    expect(salesCsv, contains('VEN-1'));
    final outside = await service.sales(
      company,
      now.subtract(const Duration(days: 10)),
      now.subtract(const Duration(days: 2)),
    );
    expect(outside, isEmpty);
    final csv = service.stockCsv(await service.stock(company));
    expect(csv, contains('Arroz'));
    expect(csv, contains('4000'));
  });
}
