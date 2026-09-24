import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';

class SaleDeliveryService {
  const SaleDeliveryService(this._db);

  final AppDatabase _db;

  Future<Result<void>> deliver({
    required SaleItem item,
    required int quantityMilli,
  }) async {
    final pending = item.quantityMilli - item.deliveredQuantityMilli;
    if (quantityMilli <= 0 || quantityMilli > pending) {
      return const Failure(
        ValidationFailure('Informe uma quantidade válida para entrega.'),
      );
    }
    try {
      final delivered = item.deliveredQuantityMilli + quantityMilli;
      await (_db.update(
        _db.saleItems,
      )..where((row) => row.id.equals(item.id))).write(
        SaleItemsCompanion(
          deliveredQuantityMilli: Value(delivered),
          deliveredAt: Value(
            delivered >= item.quantityMilli ? DateTime.now().toUtc() : null,
          ),
        ),
      );
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível registrar a entrega.', cause: error),
      );
    }
  }

  Future<Result<void>> deliverAll(List<SaleItem> items) async {
    try {
      final now = DateTime.now().toUtc();
      await _db.transaction(() async {
        for (final item in items) {
          if (item.deliveredQuantityMilli >= item.quantityMilli) continue;
          await (_db.update(
            _db.saleItems,
          )..where((row) => row.id.equals(item.id))).write(
            SaleItemsCompanion(
              deliveredQuantityMilli: Value(item.quantityMilli),
              deliveredAt: Value(now),
            ),
          );
        }
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível registrar a entrega.', cause: error),
      );
    }
  }
}
