import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

enum InventoryMovementType {
  purchase,
  sale,
  returnIn,
  adjustmentIn,
  adjustmentOut,
  transferIn,
  transferOut,
  damaged,
  expired,
  initialStock,
  production,
  cancellation,
}

class InventoryLedger {
  InventoryLedger(this._db) : _uuid = const Uuid();
  InventoryLedger.withUuid(this._db, this._uuid);
  final AppDatabase _db;
  final Uuid _uuid;

  Future<Result<int>> move({
    required String companyId,
    required String productId,
    required String warehouseId,
    required int quantityMilli,
    required InventoryMovementType type,
    required String deviceId,
    required String userId,
    required String reason,
    bool allowNegative = false,
    String? referenceId,
  }) async {
    if (quantityMilli == 0 || reason.trim().isEmpty) {
      return const Failure(
        ValidationFailure('Informe uma quantidade e um motivo.'),
      );
    }
    try {
      return await _db.transaction(() async {
        final query = _db.select(_db.inventoryBalances)
          ..where(
            (b) =>
                b.productId.equals(productId) &
                b.warehouseId.equals(warehouseId),
          );
        final current = await query.getSingleOrNull();
        final before = current?.quantityMilli ?? 0;
        final after = before + quantityMilli;
        if (after < 0 && !allowNegative) {
          return const Failure<int>(
            ValidationFailure('Stock insuficiente para concluir a operação.'),
          );
        }
        final now = DateTime.now().toUtc();
        final movementId = _uuid.v7();
        final operationId = _uuid.v7();
        await _db
            .into(_db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: movementId,
                companyId: companyId,
                productId: productId,
                warehouseId: warehouseId,
                movementType: type.name,
                quantityMilli: quantityMilli,
                balanceBeforeMilli: before,
                balanceAfterMilli: after,
                referenceId: Value(referenceId),
                reason: Value(reason.trim()),
                userId: Value(userId),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        await _db
            .into(_db.inventoryBalances)
            .insertOnConflictUpdate(
              InventoryBalancesCompanion.insert(
                productId: productId,
                warehouseId: warehouseId,
                quantityMilli: Value(after),
                updatedAt: now,
              ),
            );
        final payload = jsonEncode({
          'id': movementId,
          'companyId': companyId,
          'productId': productId,
          'warehouseId': warehouseId,
          'quantityMilli': quantityMilli,
          'type': type.name,
          'deviceId': deviceId,
          'userId': userId,
          'reason': reason.trim(),
          'createdAt': now.toIso8601String(),
        });
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: operationId,
                entityType: 'inventory_movement',
                entityId: movementId,
                operation: 'CREATE',
                deviceId: deviceId,
                payloadJson: payload,
                createdAt: now,
                version: 1,
                checksum: sha256.convert(utf8.encode(payload)).toString(),
              ),
            );
        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _uuid.v7(),
                companyId: companyId,
                userId: Value(userId),
                action: 'inventory.move',
                entityType: 'inventory_movement',
                entityId: movementId,
                afterJson: Value(payload),
                deviceId: deviceId,
                createdAt: now,
              ),
            );
        return Success(after);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível atualizar o stock.', cause: error),
      );
    }
  }
}
