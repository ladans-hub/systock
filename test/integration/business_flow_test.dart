import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/printing/pdf_receipt_printer.dart';
import 'package:systock/core/printing/receipt.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/features/purchases/application/receive_purchase.dart';
import 'package:systock/features/sales/application/complete_sale.dart';

void main() {
  test(
    'company → product → purchase → sale → receipt works entirely offline',
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
          warehouse = (await db.select(db.warehouses).getSingle()).id,
          now = DateTime.now().toUtc();
      final product =
          (await ProductCatalog(db).create(
                    companyId: company,
                    deviceId: 'd',
                    name: 'Arroz',
                    barcode: '5601234567890',
                    costMinor: 5000,
                    saleMinor: 8000,
                  )
                  as Success<String>)
              .value;
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: 'supplier',
              companyId: company,
              name: 'Fornecedor',
              createdAt: now,
              updatedAt: now,
              deviceId: 'd',
            ),
          );
      await ReceivePurchase(db)(
        companyId: company,
        supplierId: 'supplier',
        warehouseId: warehouse,
        documentNumber: 'COM-1',
        userId: user,
        deviceId: 'd',
        lines: [
          PurchaseLineInput(
            productId: product,
            quantityMilli: 10000,
            unitCostMinor: 5000,
          ),
        ],
        paidMinor: 50000,
      );
      final sale =
          (await CompleteSale(db)(
                    companyId: company,
                    warehouseId: warehouse,
                    documentNumber: 'VEN-1',
                    userId: user,
                    deviceId: 'd',
                    lines: [
                      SaleLineInput(
                        productId: product,
                        description: 'Arroz',
                        quantityMilli: 2000,
                        unitPriceMinor: 8000,
                        unitCostMinor: 5000,
                      ),
                    ],
                    payments: const [PaymentInput('cash', 16000)],
                  )
                  as Success<String>)
              .value;
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        8000,
      );
      final stored = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(sale))).getSingle();
      final pdf = await buildReceiptPdf(
        Receipt(
          company: 'Loja',
          documentNumber: stored.documentNumber,
          issuedAt: stored.createdAt,
          lines: const [
            ReceiptLine(
              description: 'Arroz',
              quantityMilli: 2000,
              unitPriceMinor: 8000,
              totalMinor: 16000,
            ),
          ],
          subtotalMinor: 16000,
          discountMinor: 0,
          totalMinor: 16000,
          payments: const {'cash': 16000},
        ),
      );
      expect(pdf.length, greaterThan(500));
    },
  );
}
