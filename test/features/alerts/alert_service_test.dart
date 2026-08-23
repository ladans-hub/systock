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
}
