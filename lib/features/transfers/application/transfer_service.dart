import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:uuid/uuid.dart';

class TransferLine {
  const TransferLine(this.productId, this.quantityMilli);
  final String productId;
  final int quantityMilli;
}

class TransferService {
  TransferService(this._db)
    : _uuid = const Uuid(),
      _ledger = InventoryLedger(_db);
  final AppDatabase _db;
  final Uuid _uuid;
  final InventoryLedger _ledger;
  Future<Result<String>> create({
    required String companyId,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required String documentNumber,
    required String userId,
    required String deviceId,
    required List<TransferLine> lines,
  }) async {
    if (sourceWarehouseId == destinationWarehouseId ||
        lines.isEmpty ||
        lines.any((l) => l.quantityMilli <= 0)) {
      return const Failure(
        ValidationFailure('Selecione armazéns diferentes e itens válidos.'),
      );
    }
    try {
      final id = _uuid.v7(), now = DateTime.now().toUtc();
      await _db.transaction(() async {
        await _db
            .into(_db.stockTransfers)
            .insert(
              StockTransfersCompanion.insert(
                id: id,
                companyId: companyId,
                documentNumber: documentNumber,
                sourceWarehouseId: sourceWarehouseId,
                destinationWarehouseId: destinationWarehouseId,
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final l in lines) {
          await _db
              .into(_db.stockTransferItems)
              .insert(
                StockTransferItemsCompanion.insert(
                  id: _uuid.v7(),
                  transferId: id,
                  productId: l.productId,
                  quantityMilli: l.quantityMilli,
                ),
              );
        }
      });
      return Success(id);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível criar a transferência.', cause: error),
      );
    }
  }

  Future<Result<void>> dispatch(String id, {required String userId}) async {
    try {
      return await _db.transaction(() async {
        final transfer =
            await (_db.select(_db.stockTransfers)
                  ..where((t) => t.id.equals(id) & t.status.equals('draft')))
                .getSingle();
        final items = await (_db.select(
          _db.stockTransferItems,
        )..where((i) => i.transferId.equals(id))).get();
        for (final item in items) {
          final result = await _ledger.move(
            companyId: transfer.companyId,
            productId: item.productId,
            warehouseId: transfer.sourceWarehouseId,
            quantityMilli: -item.quantityMilli,
            type: InventoryMovementType.transferOut,
            deviceId: transfer.deviceId,
            userId: userId,
            reason: 'Transferência ${transfer.documentNumber}',
            referenceId: id,
          );
          if (result is Failure<int>) {
            throw StateError(result.error.userMessage);
          }
        }
        await (_db.update(
          _db.stockTransfers,
        )..where((t) => t.id.equals(id))).write(
          StockTransfersCompanion(
            status: const Value('in_transit'),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
        return const Success(null);
      });
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível expedir a transferência.',
          cause: error,
        ),
      );
    }
  }

  Future<Result<void>> receive(String id, {required String userId}) async {
    try {
      return await _db.transaction(() async {
        final transfer =
            await (_db.select(_db.stockTransfers)..where(
                  (t) => t.id.equals(id) & t.status.equals('in_transit'),
                ))
                .getSingle();
        final items = await (_db.select(
          _db.stockTransferItems,
        )..where((i) => i.transferId.equals(id))).get();
        for (final item in items) {
          final result = await _ledger.move(
            companyId: transfer.companyId,
            productId: item.productId,
            warehouseId: transfer.destinationWarehouseId,
            quantityMilli: item.quantityMilli,
            type: InventoryMovementType.transferIn,
            deviceId: transfer.deviceId,
            userId: userId,
            reason: 'Recebimento ${transfer.documentNumber}',
            referenceId: id,
          );
          if (result is Failure<int>) {
            throw StateError(result.error.userMessage);
          }
        }
        await (_db.update(
          _db.stockTransfers,
        )..where((t) => t.id.equals(id))).write(
          StockTransfersCompanion(
            status: const Value('received'),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
        return const Success(null);
      });
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível receber a transferência.',
          cause: error,
        ),
      );
    }
  }
}
