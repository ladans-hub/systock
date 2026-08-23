import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/quotes/application/quote_service.dart';

void main() {
  test('creates, edits and soft-deletes a quote transactionally', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final company =
        (await SetupCompany(db)(
                  tradeName: 'Loja',
                  adminName: 'Admin',
                  username: 'admin',
                )
                as Success<String>)
            .value;
    final warehouse = await db.select(db.warehouses).getSingle();
    final user = await db.select(db.users).getSingle();
    final now = DateTime.now().toUtc();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            companyId: company,
            name: 'Produto',
            saleMinor: const Value(10000),
            createdAt: now,
            updatedAt: now,
            deviceId: 'device-a',
          ),
        );
    final service = QuoteService(db);
    final created = await service.create(
      companyId: company,
      warehouseId: warehouse.id,
      userId: user.id,
      deviceId: 'device-a',
      kind: 'quote',
      lines: const [QuoteLineInput('p1', 'Produto', 1000, 10000)],
    );
    expect(created, isA<Success<String>>());
    var quote = await db.select(db.quotes).getSingle();
    expect(quote.kind, 'quote');
    expect(quote.totalMinor, 10000);

    final edited = await service.update(
      current: quote,
      kind: 'budget',
      lines: const [QuoteLineInput('p1', 'Produto', 2000, 10000)],
    );
    expect(edited, isA<Success<void>>());
    quote = await db.select(db.quotes).getSingle();
    expect(quote.kind, 'budget');
    expect(quote.totalMinor, 20000);
    expect((await db.select(db.quoteItems).getSingle()).quantityMilli, 2000);

    expect(await service.archive(quote), isA<Success<void>>());
    expect((await db.select(db.quotes).getSingle()).deletedAt, isNotNull);
    expect(await db.select(db.quoteItems).get(), hasLength(1));
  });
}
