import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:uuid/uuid.dart';

class ReturnLineInput {
  const ReturnLineInput(
    this.saleItemId,
    this.quantityMilli, {
    this.restock = true,
  });
  final String saleItemId;
  final int quantityMilli;
  final bool restock;
}

class ReturnSale {
  ReturnSale(this._db) : _uuid = const Uuid(), _ledger = InventoryLedger(_db);
  final AppDatabase _db;
  final Uuid _uuid;
  final InventoryLedger _ledger;

  Future<Result<String>> call({
    required String saleId,
    required List<ReturnLineInput> lines,
    required String reason,
    required String userId,
    required String deviceId,
    String refundMethod = 'cash',
  }) async {
    if (lines.isEmpty ||
        reason.trim().isEmpty ||
        lines.any((l) => l.quantityMilli <= 0)) {
      return const Failure(
        ValidationFailure('Informe itens e motivo da devolução.'),
      );
    }
    try {
      return await _db.transaction(() async {
        final sale = await (_db.select(
          _db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        final previous = await _db
            .customSelect(
              'SELECT sri.sale_item_id,COALESCE(SUM(sri.quantity_milli),0) qty FROM sale_return_items sri JOIN sale_returns sr ON sr.id=sri.return_id WHERE sr.sale_id=? GROUP BY sri.sale_item_id',
              variables: [Variable(saleId)],
            )
            .get();
        final returned = {
          for (final row in previous)
            row.read<String>('sale_item_id'): row.read<int>('qty'),
        };
        final items = <(SaleItem, ReturnLineInput)>[];
        var total = 0;
        for (final input in lines) {
          final item =
              await (_db.select(_db.saleItems)..where(
                    (i) =>
                        i.id.equals(input.saleItemId) & i.saleId.equals(saleId),
                  ))
                  .getSingle();
          if ((returned[item.id] ?? 0) + input.quantityMilli >
              item.quantityMilli) {
            throw StateError('return exceeds sold quantity');
          }
          total += item.totalMinor * input.quantityMilli ~/ item.quantityMilli;
          items.add((item, input));
        }
        final now = DateTime.now().toUtc(), id = _uuid.v7();
        final number = await DocumentNumberService(_db).next(
          companyId: sale.companyId,
          type: 'sale_return',
          prefix: 'DEV',
          deviceId: deviceId,
        );
        await _db
            .into(_db.saleReturns)
            .insert(
              SaleReturnsCompanion.insert(
                id: id,
                companyId: sale.companyId,
                saleId: saleId,
                documentNumber: number,
                totalMinor: total,
                reason: reason.trim(),
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final pair in items) {
          final item = pair.$1,
              input = pair.$2,
              refund =
                  item.totalMinor * input.quantityMilli ~/ item.quantityMilli;
          await _db
              .into(_db.saleReturnItems)
              .insert(
                SaleReturnItemsCompanion.insert(
                  id: _uuid.v7(),
                  returnId: id,
                  saleItemId: item.id,
                  productId: item.productId,
                  quantityMilli: input.quantityMilli,
                  refundMinor: refund,
                  restock: Value(input.restock),
                ),
              );
          if (input.restock) {
            final movement = await _ledger.move(
              companyId: sale.companyId,
              productId: item.productId,
              warehouseId: sale.warehouseId,
              quantityMilli: input.quantityMilli,
              type: InventoryMovementType.returnIn,
              deviceId: deviceId,
              userId: userId,
              reason: 'Devolução $number',
              referenceId: id,
            );
            if (movement is Failure<int>) {
              throw StateError(movement.error.userMessage);
            }
          }
        }
        await _db
            .into(_db.payments)
            .insert(
              PaymentsCompanion.insert(
                id: _uuid.v7(),
                companyId: sale.companyId,
                saleId: saleId,
                method: 'refund_$refundMethod',
                amountMinor: -total,
                reference: Value(id),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        final totalReturned =
            (await _db
                    .customSelect(
                      'SELECT COALESCE(SUM(total_minor),0) total FROM sale_returns WHERE sale_id=?',
                      variables: [Variable(saleId)],
                    )
                    .getSingle())
                .read<int>('total');
        await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
          SalesCompanion(
            status: Value(
              totalReturned >= sale.totalMinor
                  ? 'refunded'
                  : 'partially_refunded',
            ),
            updatedAt: Value(now),
            version: Value(sale.version + 1),
          ),
        );
        return Success(id);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível processar a devolução.', cause: error),
      );
    }
  }
}
