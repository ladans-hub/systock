import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class ExpenseService {
  ExpenseService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;
  Future<Result<String>> create({
    required String companyId,
    required String categoryId,
    required String description,
    required int amountMinor,
    required String paymentMethod,
    required String userId,
    required String deviceId,
    String? cashSessionId,
  }) async {
    if (description.trim().isEmpty || amountMinor <= 0) {
      return const Failure(
        ValidationFailure('Informe uma descrição e um valor válido.'),
      );
    }
    try {
      return await _db.transaction(() async {
        final id = _uuid.v7(), now = DateTime.now().toUtc();
        await _db
            .into(_db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: id,
                companyId: companyId,
                categoryId: categoryId,
                cashSessionId: Value(cashSessionId),
                description: description.trim(),
                amountMinor: amountMinor,
                paymentMethod: paymentMethod,
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        if (cashSessionId != null) {
          await _db
              .into(_db.cashMovements)
              .insert(
                CashMovementsCompanion.insert(
                  id: _uuid.v7(),
                  cashSessionId: cashSessionId,
                  type: 'expense',
                  amountMinor: -amountMinor,
                  referenceId: Value(id),
                  reason: description.trim(),
                  userId: userId,
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
        }
        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _uuid.v7(),
                companyId: companyId,
                userId: Value(userId),
                action: 'expense.create',
                entityType: 'expense',
                entityId: id,
                deviceId: deviceId,
                createdAt: now,
              ),
            );
        return Success(id);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível registrar a despesa.', cause: error),
      );
    }
  }
}
