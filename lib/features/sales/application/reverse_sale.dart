import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:uuid/uuid.dart';

class ReverseSale {
  ReverseSale(this._db) : _ledger = InventoryLedger(_db), _uuid = const Uuid();
  final AppDatabase _db;
  final InventoryLedger _ledger;
  final Uuid _uuid;
  Future<Result<String>> call({
    required String saleId,
    required String documentNumber,
    required String userId,
    required String deviceId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      return const Failure(
        ValidationFailure('Informe o motivo do cancelamento.'),
      );
    }
    try {
      return await _db.transaction(() async {
        final original = await (_db.select(
          _db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        if (original.status == 'cancelled' || original.reversalOfId != null) {
          throw StateError('Venda já revertida');
        }
        final items = await (_db.select(
              _db.saleItems,
            )..where((i) => i.saleId.equals(saleId))).get(),
            payments = await (_db.select(
              _db.payments,
            )..where((p) => p.saleId.equals(saleId))).get();
        final reversalId = _uuid.v7(), now = DateTime.now().toUtc();
        await _db
            .into(_db.sales)
            .insert(
              SalesCompanion.insert(
                id: reversalId,
                companyId: original.companyId,
                warehouseId: original.warehouseId,
                customerId: Value(original.customerId),
                documentNumber: documentNumber,
                status: const Value('refunded'),
                subtotalMinor: -original.subtotalMinor,
                discountMinor: Value(-original.discountMinor),
                taxMinor: Value(-original.taxMinor),
                totalMinor: -original.totalMinor,
                costMinor: -original.costMinor,
                paidMinor: Value(-original.paidMinor),
                createdBy: userId,
                reversalOfId: Value(original.id),
                notes: Value(reason.trim()),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final item in items) {
          await _db
              .into(_db.saleItems)
              .insert(
                SaleItemsCompanion.insert(
                  id: _uuid.v7(),
                  saleId: reversalId,
                  productId: item.productId,
                  variantId: Value(item.variantId),
                  description: item.description,
                  quantityMilli: -item.quantityMilli,
                  unitPriceMinor: item.unitPriceMinor,
                  unitCostMinor: item.unitCostMinor,
                  discountMinor: Value(-item.discountMinor),
                  taxMinor: Value(-item.taxMinor),
                  totalMinor: -item.totalMinor,
                ),
              );
          final moved = await _ledger.move(
            companyId: original.companyId,
            productId: item.productId,
            warehouseId: original.warehouseId,
            quantityMilli: item.quantityMilli,
            type: InventoryMovementType.cancellation,
            deviceId: deviceId,
            userId: userId,
            reason: reason,
            referenceId: reversalId,
            allowNegative: true,
          );
          if (moved is Failure<int>) {
            throw StateError(moved.error.userMessage);
          }
        }
        for (final payment in payments) {
          await _db
              .into(_db.payments)
              .insert(
                PaymentsCompanion.insert(
                  id: _uuid.v7(),
                  companyId: original.companyId,
                  saleId: reversalId,
                  method: 'refund:${payment.method}',
                  amountMinor: -payment.amountMinor,
                  reference: Value(original.id),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
        }
        await (_db.update(
          _db.sales,
        )..where((s) => s.id.equals(original.id))).write(
          SalesCompanion(
            status: const Value('cancelled'),
            updatedAt: Value(now),
          ),
        );
        return Success(reversalId);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível cancelar a venda.', cause: error),
      );
    }
  }
}
