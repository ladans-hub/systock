import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:uuid/uuid.dart';

class SaleLineInput {
  const SaleLineInput({
    required this.productId,
    required this.description,
    required this.quantityMilli,
    required this.unitPriceMinor,
    required this.unitCostMinor,
    this.discountMinor = 0,
    this.taxMinor = 0,
  });
  final String productId, description;
  final int quantityMilli,
      unitPriceMinor,
      unitCostMinor,
      discountMinor,
      taxMinor;
  int get subtotalMinor => (quantityMilli * unitPriceMinor) ~/ 1000;
  int get totalMinor => subtotalMinor - discountMinor + taxMinor;
  int get costTotalMinor => (quantityMilli * unitCostMinor) ~/ 1000;
}

class PaymentInput {
  const PaymentInput(this.method, this.amountMinor, {this.reference});
  final String method;
  final int amountMinor;
  final String? reference;
}

class CompleteSale {
  CompleteSale(this._db) : _uuid = const Uuid(), _ledger = InventoryLedger(_db);
  final AppDatabase _db;
  final Uuid _uuid;
  final InventoryLedger _ledger;
  Future<Result<String>> call({
    required String companyId,
    required String warehouseId,
    required String documentNumber,
    required String userId,
    required String deviceId,
    required List<SaleLineInput> lines,
    required List<PaymentInput> payments,
    String? customerId,
    String? cashSessionId,
    DateTime? creditDueAt,
    int globalDiscountMinor = 0,
    bool deliverNow = true,
  }) async {
    if (lines.isEmpty ||
        lines.any((l) => l.quantityMilli <= 0 || l.unitPriceMinor < 0)) {
      return const Failure(
        ValidationFailure('Adicione itens válidos à venda.'),
      );
    }
    final subtotal = lines.fold<int>(0, (s, l) => s + l.subtotalMinor);
    final lineDiscount = lines.fold<int>(0, (s, l) => s + l.discountMinor);
    final tax = lines.fold<int>(0, (s, l) => s + l.taxMinor);
    final total = subtotal - lineDiscount - globalDiscountMinor + tax;
    final allocated = payments.fold<int>(0, (s, p) => s + p.amountMinor);
    final cashReceived = payments
        .where((p) => p.method == 'cash')
        .fold<int>(0, (s, p) => s + p.amountMinor);
    final credit = payments
        .where((p) => p.method == 'credit')
        .fold<int>(0, (s, p) => s + p.amountMinor);
    final change = allocated - total;
    final paid = allocated - credit - change;
    if (total < 0 ||
        allocated < total ||
        change > cashReceived ||
        (credit > 0 && (customerId == null || creditDueAt == null))) {
      return const Failure(
        ValidationFailure(
          'O pagamento deve cobrir o total; troco só pode ser devolvido em dinheiro e vendas a crédito exigem cliente e data de vencimento.',
        ),
      );
    }
    final saleId = _uuid.v7();
    final now = DateTime.now().toUtc();
    try {
      return await _db.transaction(() async {
        final cost = lines.fold<int>(0, (s, l) => s + l.costTotalMinor);
        await _db
            .into(_db.sales)
            .insert(
              SalesCompanion.insert(
                id: saleId,
                companyId: companyId,
                warehouseId: warehouseId,
                customerId: Value(customerId),
                documentNumber: documentNumber,
                status: Value(credit > 0 ? 'partially_paid' : 'paid'),
                subtotalMinor: subtotal,
                discountMinor: Value(lineDiscount + globalDiscountMinor),
                taxMinor: Value(tax),
                totalMinor: total,
                costMinor: cost,
                paidMinor: Value(paid),
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final line in lines) {
          await _db
              .into(_db.saleItems)
              .insert(
                SaleItemsCompanion.insert(
                  id: _uuid.v7(),
                  saleId: saleId,
                  productId: line.productId,
                  description: line.description,
                  quantityMilli: line.quantityMilli,
                  unitPriceMinor: line.unitPriceMinor,
                  unitCostMinor: line.unitCostMinor,
                  discountMinor: Value(line.discountMinor),
                  taxMinor: Value(line.taxMinor),
                  totalMinor: line.totalMinor,
                  deliveredQuantityMilli: Value(
                    deliverNow ? line.quantityMilli : 0,
                  ),
                  deliveredAt: Value(deliverNow ? now : null),
                ),
              );
          final product = await (_db.select(
            _db.products,
          )..where((p) => p.id.equals(line.productId))).getSingle();
          if (product.trackStock) {
            final moved = await _ledger.move(
              companyId: companyId,
              productId: line.productId,
              warehouseId: warehouseId,
              quantityMilli: -line.quantityMilli,
              type: InventoryMovementType.sale,
              deviceId: deviceId,
              userId: userId,
              reason: 'Venda $documentNumber',
              referenceId: saleId,
              allowNegative: product.allowNegativeStock,
            );
            if (moved case Failure<int>(:final error)) {
              throw _SaleFailure(error);
            }
          }
        }
        if (change > 0) {
          await _db
              .into(_db.payments)
              .insert(
                PaymentsCompanion.insert(
                  id: _uuid.v7(),
                  companyId: companyId,
                  saleId: saleId,
                  method: 'change:cash',
                  amountMinor: -change,
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
                    type: 'change',
                    amountMinor: -change,
                    referenceId: Value(saleId),
                    reason: 'Troco da venda $documentNumber',
                    userId: userId,
                    createdAt: now,
                    updatedAt: now,
                    deviceId: deviceId,
                  ),
                );
          }
        }
        for (final payment in payments) {
          await _db
              .into(_db.payments)
              .insert(
                PaymentsCompanion.insert(
                  id: _uuid.v7(),
                  companyId: companyId,
                  saleId: saleId,
                  method: payment.method,
                  amountMinor: payment.amountMinor,
                  reference: Value(payment.reference),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
          if (cashSessionId != null && payment.method == 'cash') {
            await _db
                .into(_db.cashMovements)
                .insert(
                  CashMovementsCompanion.insert(
                    id: _uuid.v7(),
                    cashSessionId: cashSessionId,
                    type: 'sale',
                    amountMinor: payment.amountMinor,
                    referenceId: Value(saleId),
                    reason: 'Venda $documentNumber',
                    userId: userId,
                    createdAt: now,
                    updatedAt: now,
                    deviceId: deviceId,
                  ),
                );
          }
        }
        final syncPayload = jsonEncode({
          'companyId': companyId,
          'warehouseId': warehouseId,
          'customerId': customerId,
          'documentNumber': documentNumber,
          'status': credit > 0 ? 'partially_paid' : 'paid',
          'subtotalMinor': subtotal,
          'discountMinor': lineDiscount + globalDiscountMinor,
          'taxMinor': tax,
          'totalMinor': total,
          'costMinor': cost,
          'paidMinor': paid,
          'deliveryStatus': deliverNow ? 'delivered' : 'pending',
          'changeMinor': change,
          'createdBy': userId,
          'createdAt': now.toIso8601String(),
          'items': [
            for (final line in lines)
              {
                'id': _uuid.v7(),
                'productId': line.productId,
                'description': line.description,
                'quantityMilli': line.quantityMilli,
                'unitPriceMinor': line.unitPriceMinor,
                'unitCostMinor': line.unitCostMinor,
                'discountMinor': line.discountMinor,
                'taxMinor': line.taxMinor,
                'totalMinor': line.totalMinor,
                'deliveredQuantityMilli': deliverNow ? line.quantityMilli : 0,
              },
          ],
          'payments': [
            for (final payment in payments)
              {
                'id': _uuid.v7(),
                'method': payment.method,
                'amountMinor': payment.amountMinor,
                'reference': payment.reference,
              },
            if (change > 0) {'method': 'change:cash', 'amountMinor': -change},
          ],
        });
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: _uuid.v7(),
                entityType: 'sale',
                entityId: saleId,
                operation: 'CREATE',
                deviceId: deviceId,
                payloadJson: syncPayload,
                createdAt: now,
                version: 1,
                checksum: sha256.convert(utf8.encode(syncPayload)).toString(),
              ),
            );
        if (credit > 0) {
          await _db
              .into(_db.customerAccountMovements)
              .insert(
                CustomerAccountMovementsCompanion.insert(
                  id: _uuid.v7(),
                  companyId: companyId,
                  customerId: customerId!,
                  saleId: Value(saleId),
                  type: 'credit_sale',
                  amountMinor: credit,
                  dueAt: Value(creditDueAt),
                  notes: Value('Venda $documentNumber'),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
          await _db.customStatement(
            'UPDATE customers SET balance_minor = balance_minor + ?, updated_at = ? WHERE id = ?',
            [credit, now.millisecondsSinceEpoch ~/ 1000, customerId],
          );
        }
        return Success(saleId);
      });
    } on _SaleFailure catch (failure) {
      return Failure(failure.error);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível finalizar a venda.', cause: error),
      );
    }
  }
}

class _SaleFailure implements Exception {
  const _SaleFailure(this.error);
  final AppFailure error;
}
