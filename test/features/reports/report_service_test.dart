import 'dart:io';
import 'package:excel_community/excel_community.dart';
import 'package:systock/features/reports/application/report_pdf.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/features/sales/application/complete_sale.dart';
import 'package:systock/features/customers/application/debt_service.dart';

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
    expect(filtered.single.product, 'Arroz');
    expect(filtered.single.quantityMilli, 1000);
    expect(filtered.single.totalMinor, 10000);
    expect(filtered.single.status, 'paid');
    expect(salesCsv, contains('Data e Hora'));
    expect(salesCsv, contains('Pago'));
    expect(salesCsv, contains('100,00 MT'));
    final from = now.subtract(const Duration(days: 1));
    final to = now.add(const Duration(days: 1));
    for (final locale in ['pt', 'en']) {
      final text = SalesReportText(locale);
      final csv = service.salesCsv(
        filtered,
        from: from,
        to: to,
        locale: locale,
      );
      expect(csv, contains(text.headers.first));
      expect(csv, contains(text.status(filtered.single)));
      final workbook = Excel.decodeBytes(
        service.salesXlsx(filtered, from: from, to: to, locale: locale),
      );
      final sheet = workbook.tables[locale == 'en' ? 'Sales' : 'Vendas']!;
      expect(
        sheet.rows[2].map((cell) => cell?.value.toString()).toList(),
        text.headers,
      );
      expect(sheet.rows[3][2]!.value.toString(), 'Arroz');
      expect(
        sheet.rows[3][3]!.value.toString(),
        locale == 'en' ? 'Paid' : 'Pago',
      );
      expect(num.parse(sheet.rows[3][4]!.value.toString()), 1);
      expect(num.parse(sheet.rows[3][5]!.value.toString()), 100);
      final pdf = await buildSalesReportPdf(
        filtered,
        'Loja',
        from,
        to,
        kpis: kpi,
        debts: const DebtSummary(
          originalMinor: 0,
          paidMinor: 0,
          outstandingMinor: 0,
          openCount: 0,
        ),
        watermark: File(
          'assets/branding/systock_logo_transparent.png',
        ).readAsBytesSync(),
        locale: locale,
      );
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    }
    // A credit sale remains visible, with payment status independent of workflow status.
    await db
        .update(db.sales)
        .write(
          const SalesCompanion(
            status: Value('partially_paid'),
            paidMinor: Value(5000),
          ),
        );
    final unpaid = await service.sales(company, from, to);
    expect(unpaid.single.status, 'unpaid');
    expect(const SalesReportText('pt').cells(unpaid.single)[3], 'Não pago');
    expect(const SalesReportText('en').cells(unpaid.single)[3], 'Unpaid');
    final sale = await db.select(db.sales).getSingle();
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            id: 'extra',
            saleId: sale.id,
            productId: 'p',
            description: 'Arroz extra',
            quantityMilli: 500,
            unitPriceMinor: 10000,
            unitCostMinor: 6000,
            totalMinor: 5000,
          ),
        );
    final detailed = await service.sales(company, from, to);
    expect(detailed, hasLength(2));
    expect(detailed.map((r) => r.totalMinor).reduce((a, b) => a + b), 15000);
    expect(detailed.map((r) => r.product), contains('Arroz extra'));

    final outside = await service.sales(
      company,
      now.subtract(const Duration(days: 10)),
      now.subtract(const Duration(days: 2)),
    );
    expect(outside, isEmpty);

    final longPdf = await buildSalesReportPdf(
      List.generate(
        300,
        (index) => SalesReportRow(
          'VEN-${index.toString().padLeft(4, '0')}',
          now,
          'paid',
          10000,
          product: 'Produto $index',
          quantityMilli: 1000,
        ),
      ),
      'Loja',
      from,
      to,
      kpis: kpi,
      debts: const DebtSummary(
        originalMinor: 0,
        paidMinor: 0,
        outstandingMinor: 0,
        openCount: 0,
      ),
      watermark: File(
        'assets/branding/systock_logo_transparent.png',
      ).readAsBytesSync(),
    );
    expect(String.fromCharCodes(longPdf.take(4)), '%PDF');

    final backgroundPdf = await buildSalesReportPdf(
      List.generate(
        643,
        (index) => SalesReportRow(
          'VEN-${index.toString().padLeft(4, '0')}',
          now,
          index.isEven ? 'paid' : 'unpaid',
          10000,
          product: 'Produto $index',
          quantityMilli: 1000,
        ),
      ),
      'Loja',
      from,
      to,
      kpis: kpi,
      debts: const DebtSummary(
        originalMinor: 10000,
        paidMinor: 5000,
        outstandingMinor: 5000,
        openCount: 1,
      ),
      locale: 'pt',
      currency: 'MZN',
      watermark: File(
        'assets/branding/systock_logo_transparent.png',
      ).readAsBytesSync(),
    );
    expect(String.fromCharCodes(backgroundPdf.take(4)), '%PDF');
    expect(backgroundPdf.length, greaterThan(1000));

    final csv = service.stockCsv(await service.stock(company));
    expect(csv, contains('Arroz'));
    expect(csv, contains('4000'));
  });
}
