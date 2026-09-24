import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/features/alerts/application/alert_service.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026);
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: 'c1',
            tradeName: 'Loja',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            companyId: 'c1',
            name: 'Arroz',
            minimumStockMilli: const Value(1000),
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
  });
  tearDown(() => db.close());

  test('refresh does not recreate a notification once it is read', () async {
    final service = AlertService(db);
    await service.refresh('c1', 'd1');
    final first = await db.select(db.notifications).getSingle();
    expect(first.readAt, isNull);

    await (db.update(db.notifications)..where((n) => n.id.equals(first.id)))
        .write(NotificationsCompanion(readAt: Value(DateTime(2026))));
    await service.refresh('c1', 'd1');

    final rows = await db.select(db.notifications).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, first.id);
    expect(rows.single.readAt, isNotNull);
  });

  test('archived and deleted notifications remain out of the inbox', () async {
    final service = AlertService(db);
    await service.refresh('c1', 'd1');
    final notification = await db.select(db.notifications).getSingle();
    final now = DateTime.utc(2026, 1, 2);

    await (db.update(db.notifications)
          ..where((n) => n.id.equals(notification.id)))
        .write(NotificationsCompanion(archivedAt: Value(now)));
    await service.refresh('c1', 'd1');
    expect(await db.select(db.notifications).get(), hasLength(1));

    await (db.update(db.notifications)
          ..where((n) => n.id.equals(notification.id)))
        .write(NotificationsCompanion(deletedAt: Value(now)));
    await service.refresh('c1', 'd1');
    expect(await db.select(db.notifications).get(), hasLength(1));
  });

  test(
    'creates expiry alert by cadence and clears it when lot is empty',
    () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.warehouses)
          .insert(
            WarehousesCompanion.insert(
              id: 'w1',
              companyId: 'c1',
              name: 'Principal',
              code: 'P',
              createdAt: now,
              updatedAt: now,
              deviceId: 'd1',
            ),
          );
      await db
          .into(db.lots)
          .insert(
            LotsCompanion.insert(
              id: 'l1',
              productId: 'p1',
              warehouseId: 'w1',
              batchNumber: 'A1',
              expiresAt: Value(now.add(const Duration(days: 6))),
              createdAt: now,
              updatedAt: now,
              deviceId: 'd1',
            ),
          );
      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: 'm1',
              companyId: 'c1',
              productId: 'p1',
              warehouseId: 'w1',
              lotId: const Value('l1'),
              movementType: 'purchase',
              quantityMilli: 10,
              balanceBeforeMilli: 0,
              balanceAfterMilli: 10,
              createdAt: now,
              updatedAt: now,
              deviceId: 'd1',
            ),
          );
      final service = AlertService(db);
      await service.refresh('c1', 'd1');
      final expiryAlert = await (db.select(
        db.notifications,
      )..where((n) => n.type.equals('expiry'))).getSingle();
      expect(expiryAlert.entityId, 'l1');
      expect(expiryAlert.title, 'Produto vence em breve');
      expect(expiryAlert.body, 'Arroz · lote A1 vence em 6 dias.');

      // Previously generated bad text must be repaired without waiting a day.
      await (db.update(
        db.notifications,
      )..where((n) => n.id.equals(expiryAlert.id))).write(
        const NotificationsCompanion(
          body: Value('Arroz · lote A1 vence em 64682696 dias.'),
        ),
      );
      await service.refresh('c1', 'd1');
      var repaired = await (db.select(
        db.notifications,
      )..where((n) => n.type.equals('expiry'))).getSingle();
      expect(repaired.id, expiryAlert.id);
      expect(repaired.body, 'Arroz · lote A1 vence em 6 dias.');

      final today = DateTime.utc(now.year, now.month, now.day);
      for (final offset in [0, 1, -1, 20]) {
        await db
            .update(db.lots)
            .write(
              LotsCompanion(
                expiresAt: Value(today.add(Duration(days: offset))),
              ),
            );
        await service.refresh('c1', 'd1');
        repaired = await (db.select(
          db.notifications,
        )..where((n) => n.type.equals('expiry'))).getSingle();
        expect(repaired.body, switch (offset) {
          0 => 'Arroz · lote A1 vence hoje.',
          1 => 'Arroz · lote A1 vence em 1 dia.',
          -1 => 'Arroz · lote A1 está vencido.',
          _ => 'Arroz · lote A1 vence em 20 dias.',
        });
      }
      await db
          .update(db.lots)
          .write(
            LotsCompanion(
              expiresAt: Value(today.add(const Duration(days: 60))),
            ),
          );
      await service.refresh('c1', 'd1');
      repaired = await (db.select(
        db.notifications,
      )..where((n) => n.type.equals('expiry'))).getSingle();
      expect(repaired.archivedAt, isNotNull);

      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: 'm2',
              companyId: 'c1',
              productId: 'p1',
              warehouseId: 'w1',
              lotId: const Value('l1'),
              movementType: 'sale',
              quantityMilli: -10,
              balanceBeforeMilli: 10,
              balanceAfterMilli: 0,
              createdAt: now,
              updatedAt: now,
              deviceId: 'd1',
            ),
          );
      await service.refresh('c1', 'd1');
      final alert = await (db.select(
        db.notifications,
      )..where((n) => n.id.equals(expiryAlert.id))).getSingle();
      expect(alert.archivedAt, isNotNull);
    },
  );

  test('updates one debt reminder every day from 7 to 1', () async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'customer',
            companyId: 'c1',
            name: 'Maria',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await db
        .into(db.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: 'warehouse',
            companyId: 'c1',
            name: 'Principal',
            code: 'P',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await db
        .into(db.roles)
        .insert(
          RolesCompanion.insert(
            id: 'role',
            companyId: 'c1',
            name: 'Administrador',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: 'user',
            companyId: 'c1',
            roleId: 'role',
            name: 'Admin',
            username: 'admin-alert',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale',
            companyId: 'c1',
            warehouseId: 'warehouse',
            customerId: const Value('customer'),
            documentNumber: 'VEN-1',
            subtotalMinor: 10000,
            totalMinor: 10000,
            costMinor: 0,
            createdBy: 'user',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    await db
        .into(db.customerAccountMovements)
        .insert(
          CustomerAccountMovementsCompanion.insert(
            id: 'debt',
            companyId: 'c1',
            customerId: 'customer',
            saleId: const Value('sale'),
            type: 'credit_sale',
            amountMinor: 10000,
            dueAt: Value(today.add(const Duration(days: 7))),
            createdAt: now,
            updatedAt: now,
            deviceId: 'd1',
          ),
        );
    final service = AlertService(db, now: () => today);
    String? notificationId;
    for (final days in [7, 6, 5, 4, 3, 2, 1]) {
      await db
          .update(db.customerAccountMovements)
          .write(
            CustomerAccountMovementsCompanion(
              dueAt: Value(today.add(Duration(days: days))),
            ),
          );
      await service.refresh('c1', 'd1');
      final alert =
          await (db.select(db.notifications)
                ..where((notification) => notification.type.equals('debt_due'))
                ..where((notification) => notification.entityId.equals('sale')))
              .getSingle();
      notificationId ??= alert.id;
      expect(alert.id, notificationId);
      expect(alert.title, 'Dívida prestes a vencer');
      expect(
        alert.body,
        'Maria · VEN-1 vence em $days ${days == 1 ? 'dia' : 'dias'}.',
      );
      await service.refresh('c1', 'd1');
      expect(
        await (db.select(db.notifications)
              ..where((notification) => notification.type.equals('debt_due'))
              ..where((notification) => notification.entityId.equals('sale')))
            .get(),
        hasLength(1),
      );
    }
  });
}
