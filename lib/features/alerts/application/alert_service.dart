import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/notifications/local_notification_service.dart';
import 'package:uuid/uuid.dart';

class AlertService {
  AlertService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;

  Future<int> refresh(
    String companyId,
    String deviceId, {
    bool notify = false,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT p.id,p.name,p.minimum_stock_milli,COALESCE(SUM(b.quantity_milli),0) qty
      FROM products p LEFT JOIN inventory_balances b ON b.product_id=p.id
      WHERE p.company_id=? AND p.deleted_at IS NULL AND p.track_stock=1
      GROUP BY p.id HAVING qty<=p.minimum_stock_milli
    ''',
          variables: [Variable(companyId)],
          readsFrom: {_db.products, _db.inventoryBalances},
        )
        .get();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      for (final row in rows) {
        final productId = row.read<String>('id');
        final qty = row.read<int>('qty'), name = row.read<String>('name');
        final title = qty == 0 ? 'Produto sem stock' : 'Stock baixo';
        final body = '$name atingiu o nível mínimo.';
        final existing =
            await (_db.select(_db.notifications)..where(
                  (n) =>
                      n.companyId.equals(companyId) &
                      n.type.equals('low_stock') &
                      n.entityId.equals(productId),
                ))
                .get();
        if (existing.isEmpty) {
          await _db
              .into(_db.notifications)
              .insert(
                NotificationsCompanion.insert(
                  id: _uuid.v7(),
                  companyId: companyId,
                  type: 'low_stock',
                  title: title,
                  body: body,
                  entityId: Value(productId),
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
        }
      }
    });
    if (notify && rows.isNotEmpty) {
      await LocalNotificationService.instance.show(
        id: 1001,
        title: 'Atenção ao stock',
        body: '${rows.length} produtos precisam de reposição.',
        payload: '/inventory',
      );
    }
    return rows.length;
  }
}
