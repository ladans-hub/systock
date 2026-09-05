import 'dart:io';
import 'package:drift/drift.dart';
import 'package:excel_community/excel_community.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/utils/money.dart';
import 'package:uuid/uuid.dart';

enum ProductImportField { ignore, name, barcode, cost, price, stock }

class ProductImportPreview {
  const ProductImportPreview(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

class ProductImportSummary {
  const ProductImportSummary(this.imported, this.warnings);
  final int imported;
  final List<String> warnings;
}

class ProductSpreadsheetService {
  ProductSpreadsheetService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;

  Future<Result<ProductImportPreview>> read(String path) async {
    try {
      final excel = Excel.decodeBytes(await File(path).readAsBytes());
      final sheet = excel.tables.values.firstOrNull;
      if (sheet == null || sheet.rows.isEmpty) {
        return const Failure(ValidationFailure('A planilha está vazia.'));
      }
      String text(Data? cell) => cell?.value?.toString().trim() ?? '';
      return Success(
        ProductImportPreview(
          sheet.rows.first.map(text).toList(),
          sheet.rows
              .skip(1)
              .map((r) => r.map(text).toList())
              .where((r) => r.any((v) => v.isNotEmpty))
              .toList(),
        ),
      );
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível ler a planilha.', cause: error),
      );
    }
  }

  Future<Result<ProductImportSummary>> import({
    required ProductImportPreview preview,
    required Map<int, ProductImportField> mapping,
    required String companyId,
    required String warehouseId,
    required String userId,
    required String deviceId,
  }) async {
    if (!mapping.containsValue(ProductImportField.name)) {
      return const Failure(ValidationFailure('Mapeie uma coluna para Nome.'));
    }
    final records = <Map<ProductImportField, String>>[], warnings = <String>[];
    for (var rowIndex = 0; rowIndex < preview.rows.length; rowIndex++) {
      final values = <ProductImportField, String>{};
      for (final entry in mapping.entries) {
        if (entry.value != ProductImportField.ignore &&
            entry.key < preview.rows[rowIndex].length) {
          values[entry.value] = preview.rows[rowIndex][entry.key].trim();
        }
      }
      if ((values[ProductImportField.name] ?? '').isEmpty) {
        warnings.add('Linha ${rowIndex + 2}: nome vazio; ignorada.');
      } else {
        records.add(values);
      }
    }
    if (records.isEmpty) {
      return Failure(
        ValidationFailure('Nenhum registro válido. ${warnings.join(' ')}'),
      );
    }
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc();
        for (final record in records) {
          final id = _uuid.v7();
          int money(ProductImportField field) {
            final raw = record[field] ?? '';
            return raw.isEmpty ? 0 : parseMoneyMinor(raw);
          }

          await _db
              .into(_db.products)
              .insert(
                ProductsCompanion.insert(
                  id: id,
                  companyId: companyId,
                  name: record[ProductImportField.name]!,
                  costMinor: Value(money(ProductImportField.cost)),
                  saleMinor: Value(money(ProductImportField.price)),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
          final barcode = _nullable(record[ProductImportField.barcode]);
          if (barcode != null) {
            await _db
                .into(_db.productBarcodes)
                .insert(
                  ProductBarcodesCompanion.insert(
                    id: _uuid.v7(),
                    productId: id,
                    barcode: barcode,
                    primaryBarcode: const Value(true),
                    createdAt: now,
                    updatedAt: now,
                    deviceId: deviceId,
                  ),
                );
          }
          final stockRaw = record[ProductImportField.stock] ?? '';
          if (stockRaw.isNotEmpty) {
            final quantityMilli = _parseQuantityMilli(stockRaw);
            if (quantityMilli != 0) {
              await _db
                  .into(_db.inventoryMovements)
                  .insert(
                    InventoryMovementsCompanion.insert(
                      id: _uuid.v7(),
                      companyId: companyId,
                      productId: id,
                      warehouseId: warehouseId,
                      movementType: 'INITIAL_STOCK',
                      quantityMilli: quantityMilli,
                      balanceBeforeMilli: 0,
                      balanceAfterMilli: quantityMilli,
                      reason: const Value('Importação de produtos'),
                      userId: Value(userId),
                      createdAt: now,
                      updatedAt: now,
                      deviceId: deviceId,
                    ),
                  );
            }
          }
        }
        await _db.rebuildInventoryBalances();
      });
      return Success(ProductImportSummary(records.length, warnings));
    } catch (error) {
      final duplicate = error.toString().contains('UNIQUE');
      return Failure(
        StorageFailure(
          duplicate
              ? 'A importação contém código de barras duplicado.'
              : 'A importação foi cancelada sem alterar os dados.',
          cause: error,
        ),
      );
    }
  }

  Future<Result<List<int>>> export(String companyId) async {
    try {
      final rows = await _db
          .customSelect(
            '''
        SELECT p.name, p.cost_minor, p.sale_minor,
          (SELECT barcode FROM product_barcodes b WHERE b.product_id=p.id AND b.deleted_at IS NULL ORDER BY primary_barcode DESC LIMIT 1) barcode,
          COALESCE(SUM(ib.quantity_milli), 0) quantity_milli
        FROM products p LEFT JOIN inventory_balances ib ON ib.product_id=p.id
        WHERE p.company_id=? AND p.deleted_at IS NULL GROUP BY p.id ORDER BY p.name COLLATE NOCASE
      ''',
            variables: [Variable(companyId)],
            readsFrom: {
              _db.products,
              _db.productBarcodes,
              _db.inventoryBalances,
            },
          )
          .get();
      final excel = Excel.createExcel();
      final sheet = excel['Produtos'];
      excel.delete('Sheet1');
      sheet.appendRow(
        [
          'Nome',
          'Código de barras',
          'Custo',
          'Preço',
          'Stock',
        ].map(TextCellValue.new).toList(),
      );
      for (final row in rows) {
        sheet.appendRow([
          TextCellValue(row.read<String>('name')),
          TextCellValue(row.readNullable<String>('barcode') ?? ''),
          TextCellValue(_minorText(row.read<int>('cost_minor'))),
          TextCellValue(_minorText(row.read<int>('sale_minor'))),
          TextCellValue(_quantityText(row.read<int>('quantity_milli'))),
        ]);
      }
      return Success(excel.save()!);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível exportar os produtos.', cause: error),
      );
    }
  }

  String? _nullable(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  int _parseQuantityMilli(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    final parts = normalized.split('.');
    final whole = int.parse(parts.first);
    final fraction = parts.length == 1
        ? 0
        : int.parse('${parts[1]}000'.substring(0, 3));
    return whole * 1000 + (whole < 0 ? -fraction : fraction);
  }

  String _minorText(int value) =>
      '${value ~/ 100},${(value.abs() % 100).toString().padLeft(2, '0')}';
  String _quantityText(int value) =>
      '${value ~/ 1000},${(value.abs() % 1000).toString().padLeft(3, '0')}';
}
