import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:uuid/uuid.dart';

class StockCountService {
  StockCountService(this._db)
    : _uuid = const Uuid(),
      _ledger = InventoryLedger(_db);
  final AppDatabase _db;
  final Uuid _uuid;
  final InventoryLedger _ledger;
  Future<Result<String>> create({
    required String companyId,
    required String warehouseId,
    required String documentNumber,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final id = _uuid.v7(), now = DateTime.now().toUtc();
      await _db.transaction(() async {
        await _db
            .into(_db.stockCounts)
            .insert(
              StockCountsCompanion.insert(
                id: id,
                companyId: companyId,
                warehouseId: warehouseId,
                documentNumber: documentNumber,
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        final products =
            await (_db.select(_db.products)..where(
                  (p) => p.companyId.equals(companyId) & p.deletedAt.isNull(),
                ))
                .get();
        for (final p in products) {
          final b =
              await (_db.select(_db.inventoryBalances)..where(
                    (b) =>
                        b.productId.equals(p.id) &
                        b.warehouseId.equals(warehouseId),
                  ))
                  .getSingleOrNull();
          await _db
              .into(_db.stockCountItems)
              .insert(
                StockCountItemsCompanion.insert(
                  id: _uuid.v7(),
                  stockCountId: id,
                  productId: p.id,
                  systemQuantityMilli: b?.quantityMilli ?? 0,
                ),
              );
        }
      });
      return Success(id);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível iniciar o inventário.', cause: error),
      );
    }
  }

  Future<Result<void>> count(String itemId, int quantityMilli) async {
    if (quantityMilli < 0) {
      return const Failure(
        ValidationFailure('A contagem não pode ser negativa.'),
      );
    }
    try {
      await (_db.update(
        _db.stockCountItems,
      )..where((i) => i.id.equals(itemId))).write(
        StockCountItemsCompanion(countedQuantityMilli: Value(quantityMilli)),
      );
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível guardar a contagem.', cause: error),
      );
    }
  }

  Future<Result<void>> approve(String id, {required String userId}) async {
    try {
      return await _db.transaction(() async {
        final count =
            await (_db.select(_db.stockCounts)
                  ..where((c) => c.id.equals(id) & c.status.equals('draft')))
                .getSingle();
        final items = await (_db.select(
          _db.stockCountItems,
        )..where((i) => i.stockCountId.equals(id))).get();
        if (items.any((i) => i.countedQuantityMilli == null)) {
          throw StateError('Existem itens não contados');
        }
        for (final item in items) {
          final difference =
              item.countedQuantityMilli! - item.systemQuantityMilli;
          if (difference != 0) {
            final moved = await _ledger.move(
              companyId: count.companyId,
              productId: item.productId,
              warehouseId: count.warehouseId,
              quantityMilli: difference,
              type: difference > 0
                  ? InventoryMovementType.adjustmentIn
                  : InventoryMovementType.adjustmentOut,
              deviceId: count.deviceId,
              userId: userId,
              reason: 'Inventário ${count.documentNumber}',
              referenceId: id,
              allowNegative: false,
            );
            if (moved is Failure<int>) {
              throw StateError(moved.error.userMessage);
            }
          }
        }
        await (_db.update(
          _db.stockCounts,
        )..where((c) => c.id.equals(id))).write(
          StockCountsCompanion(
            status: const Value('approved'),
            approvedAt: Value(DateTime.now().toUtc()),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
        return const Success(null);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível aprovar o inventário.', cause: error),
      );
    }
  }
}
