import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class CustomerDebt {
  const CustomerDebt({
    required this.saleId,
    required this.documentNumber,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
    required this.dueAt,
    required this.originalMinor,
    required this.paidMinor,
  });

  final String saleId, documentNumber, customerId, customerName;
  final DateTime createdAt;
  final DateTime? dueAt;
  final int originalMinor, paidMinor;

  int get balanceMinor => originalMinor - paidMinor;
  String get status => balanceMinor <= 0
      ? 'Liquidada'
      : paidMinor > 0
      ? 'Parcialmente liquidada'
      : 'Não liquidada';
}

class DebtSummary {
  const DebtSummary({
    required this.originalMinor,
    required this.paidMinor,
    required this.outstandingMinor,
    required this.openCount,
  });

  final int originalMinor, paidMinor, outstandingMinor, openCount;
}

class DebtService {
  DebtService(this._db) : _uuid = const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<CustomerDebt>> debts(String companyId) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT s.id sale_id, s.document_number, s.created_at, s.customer_id,
             c.name customer_name,
             COALESCE(SUM(CASE WHEN m.type='credit_sale' THEN m.amount_minor ELSE 0 END),0) original_minor,
             COALESCE(-SUM(CASE WHEN m.type='payment' THEN m.amount_minor ELSE 0 END),0) paid_minor,
             MAX(CASE WHEN m.type='credit_sale' THEN m.due_at END) due_at
      FROM sales s
      JOIN customers c ON c.id=s.customer_id
      JOIN customer_account_movements m ON m.sale_id=s.id AND m.deleted_at IS NULL
      WHERE s.company_id=? AND s.deleted_at IS NULL
      GROUP BY s.id, s.document_number, s.created_at, s.customer_id, c.name
      HAVING original_minor > 0
      ORDER BY s.created_at DESC
      ''',
          variables: [Variable<String>(companyId)],
          readsFrom: {_db.sales, _db.customers, _db.customerAccountMovements},
        )
        .get();
    return [
      for (final row in rows)
        CustomerDebt(
          saleId: row.read<String>('sale_id'),
          documentNumber: row.read<String>('document_number'),
          customerId: row.read<String>('customer_id'),
          customerName: row.read<String>('customer_name'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at') * 1000,
            isUtc: true,
          ),
          dueAt: _dateTime(row.readNullable<int>('due_at')),
          originalMinor: row.read<int>('original_minor'),
          paidMinor: row.read<int>('paid_minor'),
        ),
    ];
  }

  static DateTime? _dateTime(int? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);

  Future<DebtSummary> summary(String companyId) async {
    final rows = await debts(companyId);
    return DebtSummary(
      originalMinor: rows.fold(0, (sum, debt) => sum + debt.originalMinor),
      paidMinor: rows.fold(0, (sum, debt) => sum + debt.paidMinor),
      outstandingMinor: rows.fold(0, (sum, debt) => sum + debt.balanceMinor),
      openCount: rows.where((debt) => debt.balanceMinor > 0).length,
    );
  }

  Future<Result<void>> recordPayment({
    required CustomerDebt debt,
    required int amountMinor,
    required String deviceId,
    String? notes,
  }) async {
    if (amountMinor <= 0 || amountMinor > debt.balanceMinor) {
      return const Failure(
        ValidationFailure('Informe um valor válido até ao saldo da dívida.'),
      );
    }
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc();
        await _db
            .into(_db.customerAccountMovements)
            .insert(
              CustomerAccountMovementsCompanion.insert(
                id: _uuid.v7(),
                companyId: (await _db.select(_db.companies).getSingle()).id,
                customerId: debt.customerId,
                saleId: Value(debt.saleId),
                type: 'payment',
                amountMinor: -amountMinor,
                notes: Value(notes),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        final customer = await (_db.select(
          _db.customers,
        )..where((row) => row.id.equals(debt.customerId))).getSingle();
        await (_db.update(
          _db.customers,
        )..where((row) => row.id.equals(debt.customerId))).write(
          CustomersCompanion(
            balanceMinor: Value(customer.balanceMinor - amountMinor),
            updatedAt: Value(now),
            version: Value(customer.version + 1),
          ),
        );
        final sale = await (_db.select(
          _db.sales,
        )..where((sale) => sale.id.equals(debt.saleId))).getSingle();
        final paidMinor = (sale.paidMinor + amountMinor).clamp(
          0,
          sale.totalMinor,
        );
        await (_db.update(
          _db.sales,
        )..where((row) => row.id.equals(debt.saleId))).write(
          SalesCompanion(
            paidMinor: Value(paidMinor),
            status: Value(
              paidMinor >= sale.totalMinor ? 'paid' : 'partially_paid',
            ),
            updatedAt: Value(now),
            version: Value(sale.version + 1),
          ),
        );
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível liquidar a dívida.', cause: error),
      );
    }
  }

  Future<Result<void>> removeSettled(CustomerDebt debt) async {
    if (debt.balanceMinor > 0) {
      return const Failure(
        ValidationFailure('Apenas dívidas liquidadas podem ser removidas.'),
      );
    }
    try {
      final now = DateTime.now().toUtc();
      final movements =
          await (_db.select(_db.customerAccountMovements)..where(
                (movement) =>
                    movement.saleId.equals(debt.saleId) &
                    movement.deletedAt.isNull(),
              ))
              .get();
      await _db.transaction(() async {
        for (final movement in movements) {
          await (_db.update(
            _db.customerAccountMovements,
          )..where((row) => row.id.equals(movement.id))).write(
            CustomerAccountMovementsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              version: Value(movement.version + 1),
            ),
          );
        }
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível remover a dívida.', cause: error),
      );
    }
  }
}
