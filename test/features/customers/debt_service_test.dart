import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/customers/application/debt_service.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/sales/application/complete_sale.dart';

void main() {
  test('lists credit sale and changes debt status after payments', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final companyId =
        (await SetupCompany(db)(
                  tradeName: 'Loja',
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
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'customer',
            companyId: companyId,
            name: 'Cliente',
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'product',
            companyId: companyId,
            name: 'Produto',
            trackStock: const Value(false),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
    final sale = await CompleteSale(db)(
      companyId: companyId,
      warehouseId: warehouse.id,
      documentNumber: 'VEN-2026-000001-TEST',
      userId: user.id,
      deviceId: company.deviceId,
      customerId: 'customer',
      lines: const [
        SaleLineInput(
          productId: 'product',
          description: 'Produto',
          quantityMilli: 1000,
          unitPriceMinor: 10000,
          unitCostMinor: 4000,
        ),
      ],
      payments: const [PaymentInput('credit', 10000)],
      creditDueAt: now.add(const Duration(days: 7)),
    );
    expect(sale, isA<Success<String>>());

    final service = DebtService(db);
    var debt = (await service.debts(companyId)).single;
    expect(debt.balanceMinor, 10000);
    expect(debt.status, 'Não liquidada');
    expect(await service.removeSettled(debt), isA<Failure<void>>());

    final partialPayment = await service.recordPayment(
      debt: debt,
      amountMinor: 4000,
      deviceId: company.deviceId,
    );
    if (partialPayment case Failure(:final error)) {
      fail('${error.userMessage}: ${error.cause}');
    }
    debt = (await service.debts(companyId)).single;
    expect(debt.balanceMinor, 6000);
    expect(debt.status, 'Parcialmente liquidada');

    expect(
      await service.recordPayment(
        debt: debt,
        amountMinor: 6000,
        deviceId: company.deviceId,
      ),
      isA<Success<void>>(),
    );
    debt = (await service.debts(companyId)).single;
    expect(debt.balanceMinor, 0);
    expect(debt.status, 'Liquidada');
    expect((await db.select(db.sales).getSingle()).status, 'paid');
    expect((await db.select(db.customers).getSingle()).balanceMinor, 0);

    expect(await service.removeSettled(debt), isA<Success<void>>());
    expect(await service.debts(companyId), isEmpty);
    expect(await db.select(db.sales).get(), hasLength(1));
  });
}
