import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class PurchaseOrderLine {
  const PurchaseOrderLine(
    this.productId,
    this.quantityMilli,
    this.unitCostMinor,
  );
  final String productId;
  final int quantityMilli, unitCostMinor;
}

class PurchaseOrderService {
  PurchaseOrderService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;

  Future<Result<String>> create({
    required String companyId,
    required String supplierId,
    required String userId,
    required String deviceId,
    required List<PurchaseOrderLine> lines,
  }) async {
    if (lines.isEmpty ||
        lines.any((l) => l.quantityMilli <= 0 || l.unitCostMinor < 0)) {
      return const Failure(
        ValidationFailure('Adicione itens válidos ao pedido.'),
      );
    }
    try {
      return await _db.transaction(() async {
        final now = DateTime.now().toUtc(), id = _uuid.v7();
        final number = await DocumentNumberService(_db).next(
          companyId: companyId,
          type: 'purchase_order',
          prefix: 'PC',
          deviceId: deviceId,
        );
        final total = lines.fold<int>(
          0,
          (sum, line) => sum + line.quantityMilli * line.unitCostMinor ~/ 1000,
        );
        await _db
            .into(_db.purchaseOrders)
            .insert(
              PurchaseOrdersCompanion.insert(
                id: id,
                companyId: companyId,
                supplierId: supplierId,
                documentNumber: number,
                totalMinor: Value(total),
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        await _db.batch(
          (batch) => batch.insertAll(_db.purchaseOrderItems, [
            for (final line in lines)
              PurchaseOrderItemsCompanion.insert(
                id: _uuid.v7(),
                purchaseOrderId: id,
                productId: line.productId,
                quantityMilli: line.quantityMilli,
                unitCostMinor: line.unitCostMinor,
              ),
          ]),
        );
        return Success(id);
      });
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível criar o pedido de compra.',
          cause: error,
        ),
      );
    }
  }

  Future<Result<void>> transition(String id, String target) async {
    const allowed = {
      'draft': {'sent', 'cancelled'},
      'sent': {'partially_received', 'received', 'cancelled'},
      'partially_received': {'received', 'cancelled'},
    };
    try {
      final order = await (_db.select(
        _db.purchaseOrders,
      )..where((o) => o.id.equals(id))).getSingle();
      if (!(allowed[order.status]?.contains(target) ?? false)) {
        return const Failure(
          ValidationFailure('Transição de estado inválida.'),
        );
      }
      await (_db.update(
        _db.purchaseOrders,
      )..where((o) => o.id.equals(id))).write(
        PurchaseOrdersCompanion(
          status: Value(target),
          updatedAt: Value(DateTime.now().toUtc()),
          version: Value(order.version + 1),
        ),
      );
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível atualizar o pedido.', cause: error),
      );
    }
  }
}
