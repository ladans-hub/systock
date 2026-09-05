import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class ProductCatalog {
  ProductCatalog(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;
  Stream<List<Product>> watchPage({
    required String companyId,
    String query = '',
    int limit = 50,
    int offset = 0,
  }) {
    final term = '%${query.trim().toLowerCase()}%';
    return _db
        .customSelect(
          '''SELECT p.* FROM products p WHERE p.company_id=? AND p.deleted_at IS NULL AND (?='' OR lower(p.name) LIKE ? OR EXISTS(SELECT 1 FROM product_barcodes b WHERE b.product_id=p.id AND b.deleted_at IS NULL AND b.barcode LIKE ?)) ORDER BY p.name COLLATE NOCASE LIMIT ? OFFSET ?''',
          variables: [
            Variable(companyId),
            Variable(query.trim()),
            Variable(term),
            Variable(term),
            Variable(limit),
            Variable(offset),
          ],
          readsFrom: {_db.products, _db.productBarcodes},
        )
        .map((row) => _db.products.map(row.data))
        .watch();
  }

  Future<Result<String>> create({
    required String companyId,
    required String deviceId,
    required String name,
    String? sku,
    String? barcode,
    String? description,
    String? categoryId,
    String? brandId,
    String? unitId,
    int costMinor = 0,
    int saleMinor = 0,
    int wholesaleMinor = 0,
    int minimumPriceMinor = 0,
    int minimumStockMilli = 0,
    int maximumStockMilli = 0,
    bool trackStock = true,
    bool allowNegativeStock = false,
    int initialQuantityMilli = 0,
    String? warehouseId,
    String? userId,
  }) async {
    if (name.trim().isEmpty ||
        costMinor < 0 ||
        saleMinor < 0 ||
        initialQuantityMilli < 0 ||
        (initialQuantityMilli > 0 && (warehouseId == null || userId == null))) {
      return const Failure(
        ValidationFailure('Informe um nome e preços válidos.'),
      );
    }
    final id = _uuid.v7(), now = DateTime.now().toUtc();
    try {
      await _db.transaction(() async {
        await _db
            .into(_db.products)
            .insert(
              ProductsCompanion.insert(
                id: id,
                companyId: companyId,
                name: name.trim(),
                description: Value(description?.trim()),
                sku: Value(sku?.trim().isEmpty ?? true ? null : sku!.trim()),
                categoryId: Value(categoryId),
                brandId: Value(brandId),
                unitId: Value(unitId),
                costMinor: Value(costMinor),
                saleMinor: Value(saleMinor),
                wholesaleMinor: Value(wholesaleMinor),
                minimumPriceMinor: Value(minimumPriceMinor),
                minimumStockMilli: Value(minimumStockMilli),
                maximumStockMilli: Value(maximumStockMilli),
                trackStock: Value(trackStock),
                allowNegativeStock: Value(allowNegativeStock),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        if (barcode != null && barcode.trim().isNotEmpty) {
          await _db
              .into(_db.productBarcodes)
              .insert(
                ProductBarcodesCompanion.insert(
                  id: _uuid.v7(),
                  productId: id,
                  barcode: barcode.trim(),
                  primaryBarcode: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
        }
        if (warehouseId != null) {
          await _db
              .into(_db.inventoryBalances)
              .insert(
                InventoryBalancesCompanion.insert(
                  productId: id,
                  warehouseId: warehouseId,
                  quantityMilli: Value(initialQuantityMilli),
                  updatedAt: now,
                ),
              );
          if (initialQuantityMilli > 0) {
            final movementId = _uuid.v7();
            await _db
                .into(_db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion.insert(
                    id: movementId,
                    companyId: companyId,
                    productId: id,
                    warehouseId: warehouseId,
                    movementType: 'initialStock',
                    quantityMilli: initialQuantityMilli,
                    balanceBeforeMilli: 0,
                    balanceAfterMilli: initialQuantityMilli,
                    reason: const Value('Entrada no cadastro do produto'),
                    userId: Value(userId),
                    createdAt: now,
                    updatedAt: now,
                    deviceId: deviceId,
                  ),
                );
          }
        }
        final payload = jsonEncode({
          'companyId': companyId,
          'name': name.trim(),
          'sku': sku?.trim(),
          'barcode': barcode?.trim(),
          'costMinor': costMinor,
          'saleMinor': saleMinor,
          'wholesaleMinor': wholesaleMinor,
          'minimumPriceMinor': minimumPriceMinor,
          'minimumStockMilli': minimumStockMilli,
          'initialQuantityMilli': initialQuantityMilli,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: _uuid.v7(),
                entityType: 'product',
                entityId: id,
                operation: 'CREATE',
                deviceId: deviceId,
                payloadJson: payload,
                createdAt: now,
                version: 1,
                checksum: sha256.convert(utf8.encode(payload)).toString(),
              ),
            );
      });
      return Success(id);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível salvar o produto.', cause: error),
      );
    }
  }

  Future<Result<void>> archive(String id) async {
    try {
      await _db.transaction(() async {
        final product = await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(id))).getSingle();
        final now = DateTime.now().toUtc();
        await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
          ProductsCompanion(
            deletedAt: Value(now),
            active: const Value(false),
            updatedAt: Value(now),
            version: Value(product.version + 1),
          ),
        );
        final payload = jsonEncode({
          'deletedAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: _uuid.v7(),
                entityType: 'product',
                entityId: id,
                operation: 'DELETE',
                deviceId: product.deviceId,
                payloadJson: payload,
                createdAt: now,
                version: product.version + 1,
                checksum: sha256.convert(utf8.encode(payload)).toString(),
              ),
            );
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível arquivar o produto.', cause: error),
      );
    }
  }

  Future<Result<void>> update({
    required Product current,
    required String name,
    required int costMinor,
    required int saleMinor,
    required String deviceId,
  }) async {
    if (name.trim().isEmpty || costMinor < 0 || saleMinor < 0) {
      return const Failure(ValidationFailure('Informe nome e preços válidos.'));
    }
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc(), version = current.version + 1;
        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(current.id))).write(
          ProductsCompanion(
            name: Value(name.trim()),
            costMinor: Value(costMinor),
            saleMinor: Value(saleMinor),
            updatedAt: Value(now),
            version: Value(version),
            deviceId: Value(deviceId),
          ),
        );
        final barcode =
            await (_db.select(_db.productBarcodes)
                  ..where((b) => b.productId.equals(current.id))
                  ..limit(1))
                .getSingleOrNull();
        final payload = jsonEncode({
          'companyId': current.companyId,
          'name': name.trim(),
          'sku': current.sku,
          'barcode': barcode?.barcode,
          'costMinor': costMinor,
          'saleMinor': saleMinor,
          'createdAt': current.createdAt.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: _uuid.v7(),
                entityType: 'product',
                entityId: current.id,
                operation: 'UPDATE',
                deviceId: deviceId,
                payloadJson: payload,
                createdAt: now,
                version: version,
                checksum: sha256.convert(utf8.encode(payload)).toString(),
              ),
            );
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível atualizar o produto.', cause: error),
      );
    }
  }

  Future<Result<void>> updateComplete({
    required Product current,
    required String name,
    required String? description,
    required String? sku,
    required String? categoryId,
    required String? brandId,
    required String? unitId,
    required int costMinor,
    required int saleMinor,
    required int wholesaleMinor,
    required int minimumPriceMinor,
    required int minimumStockMilli,
    required int maximumStockMilli,
    required String? location,
    required String? shelf,
    required bool trackStock,
    required bool allowNegativeStock,
    required bool active,
    required String? barcode,
  }) async {
    if (name.trim().isEmpty ||
        [
          costMinor,
          saleMinor,
          wholesaleMinor,
          minimumPriceMinor,
        ].any((value) => value < 0)) {
      return const Failure(ValidationFailure('Informe nome e preços válidos.'));
    }
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc(), version = current.version + 1;
        String? clean(String? value) =>
            value?.trim().isEmpty ?? true ? null : value!.trim();
        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(current.id))).write(
          ProductsCompanion(
            name: Value(name.trim()),
            description: Value(clean(description)),
            sku: Value(clean(sku)),
            categoryId: Value(categoryId),
            brandId: Value(brandId),
            unitId: Value(unitId),
            costMinor: Value(costMinor),
            saleMinor: Value(saleMinor),
            wholesaleMinor: Value(wholesaleMinor),
            minimumPriceMinor: Value(minimumPriceMinor),
            minimumStockMilli: Value(minimumStockMilli),
            maximumStockMilli: Value(maximumStockMilli),
            location: Value(clean(location)),
            shelf: Value(clean(shelf)),
            trackStock: Value(trackStock),
            allowNegativeStock: Value(allowNegativeStock),
            active: Value(active),
            updatedAt: Value(now),
            version: Value(version),
          ),
        );
        final existing =
            await (_db.select(_db.productBarcodes)
                  ..where((b) => b.productId.equals(current.id))
                  ..where((b) => b.primaryBarcode.equals(true))
                  ..limit(1))
                .getSingleOrNull();
        final cleanBarcode = clean(barcode);
        if (existing != null && cleanBarcode == null) {
          await (_db.update(
            _db.productBarcodes,
          )..where((b) => b.id.equals(existing.id))).write(
            ProductBarcodesCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              version: Value(existing.version + 1),
            ),
          );
        } else if (existing != null && cleanBarcode != null) {
          await (_db.update(
            _db.productBarcodes,
          )..where((b) => b.id.equals(existing.id))).write(
            ProductBarcodesCompanion(
              barcode: Value(cleanBarcode),
              deletedAt: const Value(null),
              updatedAt: Value(now),
              version: Value(existing.version + 1),
            ),
          );
        } else if (cleanBarcode != null) {
          await _db
              .into(_db.productBarcodes)
              .insert(
                ProductBarcodesCompanion.insert(
                  id: _uuid.v7(),
                  productId: current.id,
                  barcode: cleanBarcode,
                  primaryBarcode: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: current.deviceId,
                ),
              );
        }
        final payload = jsonEncode({
          'companyId': current.companyId,
          'name': name.trim(),
          'description': clean(description),
          'sku': clean(sku),
          'barcode': cleanBarcode,
          'categoryId': categoryId,
          'brandId': brandId,
          'unitId': unitId,
          'costMinor': costMinor,
          'saleMinor': saleMinor,
          'wholesaleMinor': wholesaleMinor,
          'minimumPriceMinor': minimumPriceMinor,
          'minimumStockMilli': minimumStockMilli,
          'maximumStockMilli': maximumStockMilli,
          'updatedAt': now.toIso8601String(),
        });
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                operationId: _uuid.v7(),
                entityType: 'product',
                entityId: current.id,
                operation: 'UPDATE',
                deviceId: current.deviceId,
                payloadJson: payload,
                createdAt: now,
                version: version,
                checksum: sha256.convert(utf8.encode(payload)).toString(),
              ),
            );
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível atualizar o produto.', cause: error),
      );
    }
  }
}
