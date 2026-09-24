import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/notifications/local_notification_service.dart';
import 'package:systock/features/customers/application/debt_service.dart';
import 'package:uuid/uuid.dart';

class AlertService {
  AlertService(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _uuid = const Uuid();
  final AppDatabase _db;
  final DateTime Function() _now;
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
    final now = _now().toUtc();
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
    final today = DateTime.utc(now.year, now.month, now.day);
    final debts = (await DebtService(_db).debts(
      companyId,
    )).where((debt) => debt.balanceMinor > 0 && debt.dueAt != null).toList();
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
        // Drift stores DateTime columns as Unix timestamps, not date strings.
        final expiresAt = row.read<DateTime>('expires_at').toUtc();
        final expiryDate = DateTime.utc(
          expiresAt.year,
          expiresAt.month,
          expiresAt.day,
        );
        final today = DateTime.utc(now.year, now.month, now.day);
        final days = expiryDate.difference(today).inDays;
        final name = row.read<String>('name');
        final batch = row.read<String>('batch_number');
        final title = days < 0
            ? 'Produto vencido'
            : days <= 7
            ? 'Produto vence em breve'
            : 'Validade próxima';
        final body = days < 0
            ? '$name · lote $batch está vencido.'
            : days == 0
            ? '$name · lote $batch vence hoje.'
            : days == 1
            ? '$name · lote $batch vence em 1 dia.'
            : '$name · lote $batch vence em $days dias.';
        // Repair existing alerts immediately, even inside the reminder cadence.
        await (_db.update(_db.notifications)..where(
              (n) =>
                  n.companyId.equals(companyId) &
                  n.type.equals('expiry') &
                  n.entityId.equals(lotId) &
                  n.deletedAt.isNull() &
                  n.archivedAt.isNull(),
            ))
            .write(
              NotificationsCompanion(
                title: Value(title),
                body: Value(body),
                updatedAt: Value(now),
              ),
            );
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
        await _db
            .into(_db.notifications)
            .insert(
              NotificationsCompanion.insert(
                id: _uuid.v7(),
                companyId: companyId,
                type: 'expiry',
                title: title,
                body: body,
                entityId: Value(lotId),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
      }
      for (final debt in debts) {
        final saleId = debt.saleId;
        final dueAt = debt.dueAt!;
        final dueDate = DateTime.utc(dueAt.year, dueAt.month, dueAt.day);
        final days = dueDate.difference(today).inDays;
        if (days < 1 || days > 7) continue;
        final entityId = saleId;
        final body =
            '${debt.customerName} · ${debt.documentNumber} vence em $days ${days == 1 ? 'dia' : 'dias'}.';
        final existing =
            await (_db.select(_db.notifications)..where(
                  (n) =>
                      n.companyId.equals(companyId) &
                      n.type.equals('debt_due') &
                      n.entityId.equals(entityId),
                ))
                .getSingleOrNull();
        if (existing != null) {
          if (existing.body == body && existing.archivedAt == null) continue;
          await (_db.update(_db.notifications)
                ..where((notification) => notification.id.equals(existing.id)))
              .write(
                NotificationsCompanion(
                  title: const Value('Dívida prestes a vencer'),
                  body: Value(body),
                  readAt: const Value(null),
                  archivedAt: const Value(null),
                  updatedAt: Value(now),
                  version: Value(existing.version + 1),
                ),
              );
          continue;
        }
        await _db
            .into(_db.notifications)
            .insert(
              NotificationsCompanion.insert(
                id: _uuid.v7(),
                companyId: companyId,
                type: 'debt_due',
                title: 'Dívida prestes a vencer',
                body: body,
                entityId: Value(entityId),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
      }
      final debtAlerts =
          await (_db.select(_db.notifications)..where(
                (n) =>
                    n.companyId.equals(companyId) &
                    n.type.equals('debt_due') &
                    n.deletedAt.isNull() &
                    n.archivedAt.isNull(),
              ))
              .get();
      for (final alert in debtAlerts) {
        final saleId = alert.entityId;
        final stillOpen = debts.any((debt) => debt.saleId == saleId);
        final debt = debts.where((debt) => debt.saleId == saleId).firstOrNull;
        if (stillOpen && debt != null) {
          final dueAt = debt.dueAt!;
          final dueDate = DateTime.utc(dueAt.year, dueAt.month, dueAt.day);
          final days = dueDate.difference(today).inDays;
          if (days >= 1 && days <= 7) continue;
        }
        await (_db.update(
          _db.notifications,
        )..where((notification) => notification.id.equals(alert.id))).write(
          NotificationsCompanion(
            archivedAt: Value(now),
            readAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
    final debtDueCount = debts.where((debt) {
      final dueAt = debt.dueAt!;
      final dueDate = DateTime.utc(dueAt.year, dueAt.month, dueAt.day);
      final days = dueDate.difference(today).inDays;
      return days >= 1 && days <= 7;
    }).length;
    if (notify &&
        (rows.isNotEmpty || expiryRows.isNotEmpty || debtDueCount > 0)) {
      await LocalNotificationService.instance.show(
        id: 1001,
        title: debtDueCount > 0
            ? 'Dívidas prestes a vencer'
            : expiryRows.isNotEmpty
            ? 'Atenção às validades'
            : 'Atenção ao stock',
        body: debtDueCount > 0
            ? '$debtDueCount dívidas precisam de atenção.'
            : expiryRows.isNotEmpty
            ? '${expiryRows.length} lotes precisam de atenção.'
            : '${rows.length} produtos precisam de reposição.',
        payload: debtDueCount > 0
            ? '/debts'
            : expiryRows.isNotEmpty
            ? '/inventory/lots'
            : '/inventory',
      );
    }
    return rows.length + expiryRows.length + debtDueCount;
  }
}
