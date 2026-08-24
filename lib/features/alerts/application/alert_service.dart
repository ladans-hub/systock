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
    final expiryRows = await _db
        .customSelect(
          '''
      SELECT l.id lot_id, l.batch_number, l.expires_at, p.name,
             COALESCE(
               (SELECT SUM(im.quantity_milli)
                  FROM inventory_movements im
                 WHERE im.lot_id=l.id AND im.deleted_at IS NULL),
               (SELECT SUM(ib.quantity_milli)
                  FROM inventory_balances ib
                 WHERE ib.product_id=l.product_id),
               0
             ) qty
      FROM lots l JOIN products p ON p.id=l.product_id
      WHERE p.company_id=? AND p.deleted_at IS NULL AND l.deleted_at IS NULL
        AND l.expires_at IS NOT NULL AND l.expires_at <= ?
      GROUP BY l.id, l.batch_number, l.expires_at, p.name
      HAVING qty > 0
      ''',
          variables: [
            Variable(companyId),
            Variable(now.add(const Duration(days: 30))),
          ],
          readsFrom: {
            _db.lots,
            _db.products,
            _db.inventoryMovements,
            _db.inventoryBalances,
          },
        )
        .get();
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
      final activeProducts = rows.map((r) => r.read<String>('id')).toSet();
      final stockAlerts =
          await (_db.select(_db.notifications)..where(
                (n) =>
                    n.companyId.equals(companyId) &
                    n.type.equals('low_stock') &
                    n.deletedAt.isNull(),
              ))
              .get();
      for (final alert in stockAlerts) {
        if (!activeProducts.contains(alert.entityId)) {
          await (_db.update(
            _db.notifications,
          )..where((n) => n.id.equals(alert.id))).write(
            NotificationsCompanion(
              archivedAt: Value(now),
              readAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        }
      }
      final activeLots = expiryRows
          .map((r) => r.read<String>('lot_id'))
          .toSet();
      final expiryAlerts =
          await (_db.select(_db.notifications)..where(
                (n) =>
                    n.companyId.equals(companyId) &
                    n.type.equals('expiry') &
                    n.deletedAt.isNull(),
              ))
              .get();
      for (final alert in expiryAlerts) {
        if (!activeLots.contains(alert.entityId)) {
          await (_db.update(
            _db.notifications,
          )..where((n) => n.id.equals(alert.id))).write(
            NotificationsCompanion(
              archivedAt: Value(now),
              readAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        }
      }
      for (final row in expiryRows) {
        final lotId = row.read<String>('lot_id');
        final expiresAt = DateTime.parse(
          row.read<String>('expires_at'),
        ).toUtc();
        final days = expiresAt.difference(now).inDays;
        final cadence = days <= 7
            ? const Duration(days: 1)
            : const Duration(days: 7);
        final last =
            await (_db.select(_db.notifications)
                  ..where(
                    (n) =>
                        n.companyId.equals(companyId) &
                        n.type.equals('expiry') &
                        n.entityId.equals(lotId),
                  )
                  ..orderBy([(n) => OrderingTerm.desc(n.createdAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (last != null && now.difference(last.createdAt) < cadence) continue;
        final name = row.read<String>('name');
        final batch = row.read<String>('batch_number');
        await _db
            .into(_db.notifications)
            .insert(
              NotificationsCompanion.insert(
                id: _uuid.v7(),
                companyId: companyId,
                type: 'expiry',
                title: days < 0
                    ? 'Produto vencido'
                    : days <= 7
                    ? 'Produto vence em breve'
                    : 'Validade próxima',
                body: days < 0
                    ? '$name · lote $batch está vencido.'
                    : '$name · lote $batch vence em $days dias.',
                entityId: Value(lotId),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
      }
    });
    if (notify && (rows.isNotEmpty || expiryRows.isNotEmpty)) {
      await LocalNotificationService.instance.show(
        id: 1001,
        title: expiryRows.isNotEmpty
            ? 'Atenção às validades'
            : 'Atenção ao stock',
        body: expiryRows.isNotEmpty
            ? '${expiryRows.length} lotes precisam de atenção.'
            : '${rows.length} produtos precisam de reposição.',
        payload: expiryRows.isNotEmpty ? '/inventory/lots' : '/inventory',
      );
    }
    return rows.length + expiryRows.length;
  }
}
