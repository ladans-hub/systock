import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class CustomerCreditService {
  CustomerCreditService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;

  Future<Result<void>> recordPayment({
    required String customerId,
    required int amountMinor,
    required String deviceId,
    String? notes,
  }) async {
    if (amountMinor <= 0) {
      return const Failure(ValidationFailure('Informe um valor positivo.'));
    }
    try {
      await _db.transaction(() async {
        final customer = await (_db.select(
          _db.customers,
        )..where((c) => c.id.equals(customerId))).getSingle();
        if (amountMinor > customer.balanceMinor) {
          throw StateError('payment exceeds balance');
        }
        final now = DateTime.now().toUtc();
        await _db
            .into(_db.customerAccountMovements)
            .insert(
              CustomerAccountMovementsCompanion.insert(
                id: _uuid.v7(),
                companyId: customer.companyId,
                customerId: customerId,
                type: 'payment',
                amountMinor: -amountMinor,
                notes: Value(notes),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        await _db.customStatement(
          'UPDATE customers SET balance_minor=balance_minor-?, updated_at=? WHERE id=?',
          [amountMinor, now, customerId],
        );
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível registrar o pagamento. Verifique o saldo.',
          cause: error,
        ),
      );
    }
  }
}
