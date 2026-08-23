import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/cash/application/cash_session_service.dart';
import 'package:systock/features/expenses/application/expense_service.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test('cash expense and negative cash movement commit together', () async {
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
    await db
        .into(db.cashRegisters)
        .insert(
          CashRegistersCompanion.insert(
            id: 'r',
            companyId: company,
            warehouseId: warehouse,
            name: 'Caixa',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd',
          ),
        );
    final session =
        (await CashSessionService(db).open(
                  registerId: 'r',
                  userId: user,
                  deviceId: 'd',
                  openingMinor: 10000,
                )
                as Success<String>)
            .value;
    await db
        .into(db.expenseCategories)
        .insert(
          ExpenseCategoriesCompanion.insert(
            id: 'cat',
            companyId: company,
            name: 'Energia',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd',
          ),
        );
    final result = await ExpenseService(db).create(
      companyId: company,
      categoryId: 'cat',
      description: 'Conta',
      amountMinor: 2000,
      paymentMethod: 'cash',
      userId: user,
      deviceId: 'd',
      cashSessionId: session,
    );
    expect(result, isA<Success<String>>());
    expect((await db.select(db.cashMovements).getSingle()).amountMinor, -2000);
    expect(await db.select(db.auditLogs).get(), hasLength(1));
  });
}
