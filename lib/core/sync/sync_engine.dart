import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/sync/sync_transport.dart';

class SyncSummary {
  const SyncSummary(this.uploaded, this.applied, this.ignored);
  final int uploaded, applied, ignored;
}

class SyncEngine {
  const SyncEngine(this._db, this._transport);
  final AppDatabase _db;
  final SyncTransport _transport;
  Future<Result<SyncSummary>> synchronize() async {
    try {
      final pending = await (_db.select(
        _db.syncOperations,
      )..where((o) => o.status.equals('pending'))).get();
      final outbound = [
        for (final o in pending)
          SyncEnvelope(
            operationId: o.operationId,
            deviceId: o.deviceId,
            entityType: o.entityType,
            entityId: o.entityId,
            operation: o.operation,
            version: o.version,
            payloadJson: o.payloadJson,
            checksum: o.checksum,
            createdAt: o.createdAt,
          ),
      ];
      await _transport.upload(outbound);
      if (pending.isNotEmpty) {
        await (_db.update(_db.syncOperations)..where(
              (o) => o.operationId.isIn(pending.map((p) => p.operationId)),
            ))
            .write(const SyncOperationsCompanion(status: Value('synced')));
      }
      final appliedIds =
          (await _db.select(_db.appliedOperations).get())
              .map((a) => a.operationId)
              .toSet()
            ..addAll(pending.map((p) => p.operationId));
      final incoming = await _transport.download(
        excludingOperationIds: appliedIds,
      );
      var applied = 0, ignored = 0;
      for (final op in incoming) {
        if (sha256.convert(utf8.encode(op.payloadJson)).toString() !=
            op.checksum) {
          ignored++;
          continue;
        }
        final didApply = await _db.transaction(() => _apply(op));
        if (didApply) {
          applied++;
        } else {
          ignored++;
        }
      }
      if (applied > 0) {
        await _db.rebuildInventoryBalances();
      }
      return Success(SyncSummary(outbound.length, applied, ignored));
    } catch (error) {
      return Failure(
        StorageFailure(
          'Não foi possível sincronizar. Os dados continuam seguros neste dispositivo.',
          cause: error,
        ),
      );
    }
  }

  Future<bool> _apply(SyncEnvelope op) async {
    if (await (_db.select(_db.appliedOperations)
              ..where((a) => a.operationId.equals(op.operationId)))
            .getSingleOrNull() !=
        null) {
      return false;
    }
    if (op.entityType == 'product') {
      await _applyProduct(op);
    } else if (op.entityType == 'sale' && op.operation == 'CREATE') {
      await _applySale(op);
    } else if (op.entityType == 'inventory_movement' &&
        op.operation == 'CREATE') {
      final p = jsonDecode(op.payloadJson) as Map<String, dynamic>;
      final exists = await (_db.select(
        _db.inventoryMovements,
      )..where((m) => m.id.equals(op.entityId))).getSingleOrNull();
      if (exists == null) {
        final at = DateTime.parse(p['createdAt'] as String);
        await _db
            .into(_db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: op.entityId,
                companyId: p['companyId'] as String,
                productId: p['productId'] as String,
                warehouseId: p['warehouseId'] as String,
                movementType: p['type'] as String,
                quantityMilli: p['quantityMilli'] as int,
                balanceBeforeMilli: 0,
                balanceAfterMilli: 0,
                reason: Value(p['reason'] as String?),
                userId: Value(p['userId'] as String?),
                createdAt: at,
                updatedAt: at,
                deviceId: op.deviceId,
              ),
            );
      }
    }
    await _db
        .into(_db.appliedOperations)
        .insert(
          AppliedOperationsCompanion.insert(
            operationId: op.operationId,
            appliedAt: DateTime.now().toUtc(),
            sourceDeviceId: op.deviceId,
          ),
        );
    return true;
  }

  Future<void> _applyProduct(SyncEnvelope op) async {
    final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
    final local = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(op.entityId))).getSingleOrNull();
    if (local != null && local.version >= op.version) return;
    if (local != null &&
        local.updatedAt.isAfter(op.createdAt) &&
        local.deviceId != op.deviceId) {
      await _db
          .into(_db.syncConflicts)
          .insert(
            SyncConflictsCompanion.insert(
              id: op.operationId,
              entityType: 'product',
              entityId: op.entityId,
              localPayloadJson: jsonEncode({
                'name': local.name,
                'sku': local.sku,
                'version': local.version,
              }),
              remotePayloadJson: op.payloadJson,
              createdAt: DateTime.now().toUtc(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }
    if (op.operation == 'DELETE') {
      if (local != null) {
        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(op.entityId))).write(
          ProductsCompanion(
            deletedAt: Value(DateTime.parse(payload['deletedAt'] as String)),
            active: const Value(false),
            updatedAt: Value(DateTime.parse(payload['updatedAt'] as String)),
            version: Value(op.version),
          ),
        );
      }
      return;
    }
    if (local == null) {
      final created = DateTime.parse(payload['createdAt'] as String),
          updated = DateTime.parse(payload['updatedAt'] as String);
      await _db
          .into(_db.products)
          .insert(
            ProductsCompanion.insert(
              id: op.entityId,
              companyId: payload['companyId'] as String,
              name: payload['name'] as String,
              sku: Value(payload['sku'] as String?),
              costMinor: Value(payload['costMinor'] as int),
              saleMinor: Value(payload['saleMinor'] as int),
              createdAt: created,
              updatedAt: updated,
              version: Value(op.version),
              deviceId: op.deviceId,
            ),
          );
      final barcode = payload['barcode'] as String?;
      if (barcode != null && barcode.isNotEmpty) {
        await _db
            .into(_db.productBarcodes)
            .insert(
              ProductBarcodesCompanion.insert(
                id: '${op.operationId}-barcode',
                productId: op.entityId,
                barcode: barcode,
                primaryBarcode: const Value(true),
                createdAt: created,
                updatedAt: updated,
                deviceId: op.deviceId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    } else {
      await (_db.update(
        _db.products,
      )..where((p) => p.id.equals(op.entityId))).write(
        ProductsCompanion(
          name: Value(payload['name'] as String),
          sku: Value(payload['sku'] as String?),
          costMinor: Value(payload['costMinor'] as int),
          saleMinor: Value(payload['saleMinor'] as int),
          updatedAt: Value(DateTime.parse(payload['updatedAt'] as String)),
          version: Value(op.version),
          deviceId: Value(op.deviceId),
        ),
      );
    }
  }

  Future<void> _applySale(SyncEnvelope op) async {
    final exists = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(op.entityId))).getSingleOrNull();
    if (exists != null) return;
    final p = jsonDecode(op.payloadJson) as Map<String, dynamic>;
    final at = DateTime.parse(p['createdAt'] as String);
    String? customerId = p['customerId'] as String?;
    if (customerId != null &&
        await (_db.select(
              _db.customers,
            )..where((c) => c.id.equals(customerId!))).getSingleOrNull() ==
            null) {
      customerId = null;
    }
    await _db
        .into(_db.sales)
        .insert(
          SalesCompanion.insert(
            id: op.entityId,
            companyId: p['companyId'] as String,
            warehouseId: p['warehouseId'] as String,
            customerId: Value(customerId),
            documentNumber: p['documentNumber'] as String,
            status: Value(p['status'] as String),
            subtotalMinor: p['subtotalMinor'] as int,
            discountMinor: Value(p['discountMinor'] as int),
            taxMinor: Value(p['taxMinor'] as int),
            totalMinor: p['totalMinor'] as int,
            costMinor: p['costMinor'] as int,
            paidMinor: Value(p['paidMinor'] as int),
            createdBy: p['createdBy'] as String,
            createdAt: at,
            updatedAt: at,
            deviceId: op.deviceId,
          ),
        );
    for (final item
        in (p['items'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      await _db
          .into(_db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              id: item['id'] as String,
              saleId: op.entityId,
              productId: item['productId'] as String,
              description: item['description'] as String,
              quantityMilli: item['quantityMilli'] as int,
              unitPriceMinor: item['unitPriceMinor'] as int,
              unitCostMinor: item['unitCostMinor'] as int,
              discountMinor: Value(item['discountMinor'] as int),
              taxMinor: Value(item['taxMinor'] as int),
              totalMinor: item['totalMinor'] as int,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final payment
        in (p['payments'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      await _db
          .into(_db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: payment['id'] as String,
              companyId: p['companyId'] as String,
              saleId: op.entityId,
              method: payment['method'] as String,
              amountMinor: payment['amountMinor'] as int,
              reference: Value(payment['reference'] as String?),
              createdAt: at,
              updatedAt: at,
              deviceId: op.deviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
}
