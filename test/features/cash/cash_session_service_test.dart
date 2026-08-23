import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/cash/application/cash_session_service.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test('cash close calculates expected and counted difference', () async {
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
                  openingMinor: 1000,
                )
                as Success<String>)
            .value;
    await db
        .into(db.cashMovements)
        .insert(
          CashMovementsCompanion.insert(
            id: 'm',
            cashSessionId: session,
            type: 'sale',
            amountMinor: 500,
            reason: 'Venda',
            userId: user,
            createdAt: now,
            updatedAt: now,
            deviceId: 'd',
          ),
        );
    final result =
        await CashSessionService(
              db,
            ).close(sessionId: session, userId: user, countedMinor: 1400)
            as Success<int>;
    expect(result.value, -100);
    expect((await db.select(db.cashSessions).getSingle()).status, 'closed');
  });
}
