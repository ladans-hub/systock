import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:uuid/uuid.dart';

class PurchaseLineInput {
  const PurchaseLineInput({
    required this.productId,
    required this.quantityMilli,
    required this.unitCostMinor,
  });
  final String productId;
  final int quantityMilli;
  final int unitCostMinor;
  int get totalMinor => (quantityMilli * unitCostMinor) ~/ 1000;
}

class ReceivePurchase {
  ReceivePurchase(this._db)
    : _uuid = const Uuid(),
      _ledger = InventoryLedger(_db);
  final AppDatabase _db;
  final Uuid _uuid;
  final InventoryLedger _ledger;

  Future<Result<String>> call({
    required String companyId,
    required String supplierId,
    required String warehouseId,
    required String documentNumber,
    required String userId,
    required String deviceId,
    required List<PurchaseLineInput> lines,
    String? purchaseOrderId,
    int discountMinor = 0,
    int taxMinor = 0,
    int additionalCostsMinor = 0,
    int paidMinor = 0,
  }) async {
    if (lines.isEmpty ||
        lines.any(
          (line) => line.quantityMilli <= 0 || line.unitCostMinor < 0,
        )) {
      return const Failure(
        ValidationFailure('Adicione itens válidos à compra.'),
      );
    }
    final subtotal = lines.fold<int>(0, (sum, line) => sum + line.totalMinor);
    final total = subtotal - discountMinor + taxMinor + additionalCostsMinor;
    if (total < 0 || paidMinor < 0 || paidMinor > total) {
      return const Failure(
        ValidationFailure('Os totais ou pagamentos da compra são inválidos.'),
      );
    }
    final id = _uuid.v7();
    final now = DateTime.now().toUtc();
    try {
      return await _db.transaction(() async {
        await _db
            .into(_db.purchases)
            .insert(
              PurchasesCompanion.insert(
                id: id,
                companyId: companyId,
                supplierId: supplierId,
                warehouseId: warehouseId,
                purchaseOrderId: Value(purchaseOrderId),
                documentNumber: documentNumber,
                status: Value(paidMinor == total ? 'paid' : 'received'),
                subtotalMinor: subtotal,
                discountMinor: Value(discountMinor),
                taxMinor: Value(taxMinor),
                additionalCostsMinor: Value(additionalCostsMinor),
                totalMinor: total,
                paidMinor: Value(paidMinor),
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final line in lines) {
          await _db
              .into(_db.purchaseItems)
              .insert(
                PurchaseItemsCompanion.insert(
                  id: _uuid.v7(),
                  purchaseId: id,
                  productId: line.productId,
                  quantityMilli: line.quantityMilli,
                  unitCostMinor: line.unitCostMinor,
                  totalMinor: line.totalMinor,
                ),
              );
          final movement = await _ledger.move(
            companyId: companyId,
            productId: line.productId,
            warehouseId: warehouseId,
            quantityMilli: line.quantityMilli,
            type: InventoryMovementType.purchase,
            deviceId: deviceId,
            userId: userId,
            reason: 'Recebimento $documentNumber',
            referenceId: id,
          );
          if (movement is Failure<int>) {
            throw StateError(movement.error.userMessage);
          }
          await (_db.update(
            _db.products,
          )..where((p) => p.id.equals(line.productId))).write(
            ProductsCompanion(
              costMinor: Value(line.unitCostMinor),
              updatedAt: Value(now),
            ),
          );
        }
        if (purchaseOrderId != null) {
          for (final line in lines) {
            await _db.customStatement(
              'UPDATE purchase_order_items SET received_quantity_milli = MIN(quantity_milli, received_quantity_milli + ?) WHERE purchase_order_id=? AND product_id=?',
              [line.quantityMilli, purchaseOrderId, line.productId],
            );
          }
          final remaining = await _db
              .customSelect(
                'SELECT COUNT(*) count FROM purchase_order_items WHERE purchase_order_id=? AND received_quantity_milli<quantity_milli',
                variables: [Variable(purchaseOrderId)],
              )
              .getSingle();
          await (_db.update(
            _db.purchaseOrders,
          )..where((o) => o.id.equals(purchaseOrderId))).write(
            PurchaseOrdersCompanion(
              status: Value(
                remaining.read<int>('count') == 0
                    ? 'received'
                    : 'partially_received',
              ),
              updatedAt: Value(now),
            ),
          );
        }
        return Success(id);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível receber a compra.', cause: error),
      );
    }
  }
}
