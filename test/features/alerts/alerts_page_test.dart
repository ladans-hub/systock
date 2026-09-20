import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/widgets/notification_bell.dart';
import 'package:systock/features/alerts/presentation/alerts_page.dart';

void main() {
  testWidgets('reading retains notification and updates bold and bell count', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026);
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: 'c',
            tradeName: 'Loja',
            createdAt: now,
            updatedAt: now,
            deviceId: 'd',
          ),
        );
    for (final id in ['first', 'second', 'archived', 'deleted']) {
      await db
          .into(db.notifications)
          .insert(
            NotificationsCompanion.insert(
              id: id,
              companyId: 'c',
              type: 'low_stock',
              title: id,
              body: 'Alerta $id',
              createdAt: now,
              updatedAt: now,
              deviceId: 'd',
              archivedAt: Value(id == 'archived' ? now : null),
              deletedAt: Value(id == 'deleted' ? now : null),
            ),
          );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: NotificationBell(),
            ),
            body: AlertsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Badge badge() => tester.widget<Badge>(find.byType(Badge));
    expect((badge().label! as Text).data, '2');
    expect(
      tester.widget<Text>(find.text('first')).style!.fontWeight,
      FontWeight.bold,
    );
    expect(find.text('archived'), findsNothing);
    expect(find.text('deleted'), findsNothing);

    await tester.tap(find.text('first'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('first')).style!.fontWeight,
      FontWeight.normal,
    );
    expect((badge().label! as Text).data, '1');
    final first = await (db.select(
      db.notifications,
    )..where((n) => n.id.equals('first'))).getSingle();
    expect(first.readAt, isNotNull);
    expect(first.archivedAt, isNull);
    expect(first.deletedAt, isNull);

    await tester.tap(find.text('first'));
    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();
    expect(badge().isLabelVisible, isFalse);
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    final reread = await (db.select(
      db.notifications,
    )..where((n) => n.id.equals('first'))).getSingle();
    expect(reread.readAt, first.readAt);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
