import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class QuoteLineInput {
  const QuoteLineInput(
    this.productId,
    this.description,
    this.quantityMilli,
    this.unitPriceMinor,
  );
  final String productId, description;
  final int quantityMilli, unitPriceMinor;
  int get totalMinor => quantityMilli * unitPriceMinor ~/ 1000;
}

class QuoteService {
  QuoteService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;

  Future<Result<String>> create({
    required String companyId,
    required String warehouseId,
    required String userId,
    required String deviceId,
    required String kind,
    required List<QuoteLineInput> lines,
    String? customerId,
    DateTime? validUntil,
  }) async {
    if (!{'quote', 'budget'}.contains(kind)) {
      return const Failure(ValidationFailure('Tipo de documento inválido.'));
    }
    if (lines.isEmpty ||
        lines.any((l) => l.quantityMilli <= 0 || l.unitPriceMinor < 0)) {
      return const Failure(ValidationFailure('Adicione itens válidos.'));
    }
    try {
      return await _db.transaction(() async {
        final now = DateTime.now().toUtc(), id = _uuid.v7();
        final prefix = switch (kind) {
          'budget' => 'ORC',
          _ => 'COT',
        };
        final number = await DocumentNumberService(_db).next(
          companyId: companyId,
          type: kind,
          prefix: prefix,
          deviceId: deviceId,
        );
        final total = lines.fold<int>(0, (sum, line) => sum + line.totalMinor);
        await _db
            .into(_db.quotes)
            .insert(
              QuotesCompanion.insert(
                id: id,
                companyId: companyId,
                customerId: Value(customerId),
                warehouseId: warehouseId,
                documentNumber: number,
                kind: Value(kind),
                totalMinor: total,
                validUntil: Value(validUntil),
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        await _db.batch(
          (batch) => batch.insertAll(_db.quoteItems, [
            for (final line in lines)
              QuoteItemsCompanion.insert(
                id: _uuid.v7(),
                quoteId: id,
                productId: line.productId,
                description: line.description,
                quantityMilli: line.quantityMilli,
                unitPriceMinor: line.unitPriceMinor,
                totalMinor: line.totalMinor,
              ),
          ]),
        );
        return Success(id);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível criar a cotação.', cause: error),
      );
    }
  }

  Future<Result<void>> update({
    required Quote current,
    required String kind,
    required List<QuoteLineInput> lines,
  }) async {
    if (!{'quote', 'budget'}.contains(kind) ||
        lines.isEmpty ||
        lines.any(
          (line) => line.quantityMilli <= 0 || line.unitPriceMinor < 0,
        )) {
      return const Failure(ValidationFailure('Adicione itens válidos.'));
    }
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc();
        final version = current.version + 1;
        final total = lines.fold<int>(0, (sum, line) => sum + line.totalMinor);
        await (_db.update(
          _db.quotes,
        )..where((q) => q.id.equals(current.id))).write(
          QuotesCompanion(
            kind: Value(kind),
            totalMinor: Value(total),
            updatedAt: Value(now),
            version: Value(version),
          ),
        );
        await (_db.delete(
          _db.quoteItems,
        )..where((item) => item.quoteId.equals(current.id))).go();
        await _db.batch(
          (batch) => batch.insertAll(_db.quoteItems, [
            for (final line in lines)
              QuoteItemsCompanion.insert(
                id: _uuid.v7(),
                quoteId: current.id,
                productId: line.productId,
                description: line.description,
                quantityMilli: line.quantityMilli,
                unitPriceMinor: line.unitPriceMinor,
                totalMinor: line.totalMinor,
              ),
          ]),
        );
        await _writeOperation(current, 'UPDATE', version, now, {
          'kind': kind,
          'totalMinor': total,
          'lines': [
            for (final line in lines)
              {
                'productId': line.productId,
                'description': line.description,
                'quantityMilli': line.quantityMilli,
                'unitPriceMinor': line.unitPriceMinor,
              },
          ],
        });
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível editar o documento.', cause: error),
      );
    }
  }

  Future<Result<void>> archive(Quote current) async {
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc(), version = current.version + 1;
        await (_db.update(
          _db.quotes,
        )..where((q) => q.id.equals(current.id))).write(
          QuotesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            version: Value(version),
          ),
        );
        await _writeOperation(current, 'DELETE', version, now, {
          'deletedAt': now.toIso8601String(),
        });
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível apagar o documento.', cause: error),
      );
    }
  }

  Future<void> _writeOperation(
    Quote quote,
    String operation,
    int version,
    DateTime now,
    Map<String, Object?> data,
  ) async {
    final payload = jsonEncode({...data, 'updatedAt': now.toIso8601String()});
    await _db
        .into(_db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            operationId: _uuid.v7(),
            entityType: 'quote',
            entityId: quote.id,
            operation: operation,
            deviceId: quote.deviceId,
            payloadJson: payload,
            createdAt: now,
            version: version,
            checksum: sha256.convert(utf8.encode(payload)).toString(),
          ),
        );
  }
}
