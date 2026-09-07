import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/products/application/product_catalog.dart';

void main() {
  test(
    'creates product and searches by barcode without loading full table',
    () async {
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
      final result = await ProductCatalog(db).create(
        companyId: company,
        deviceId: 'd',
        name: 'Coca-Cola 2L',
        barcode: '5601234567890',
        saleMinor: 15000,
      );
      expect(result, isA<Success<String>>());
      final page = await ProductCatalog(
        db,
      ).watchPage(companyId: company, query: '5601234567890', limit: 20).first;
      expect(page.single.name, 'Coca-Cola 2L');
    },
  );
  test('initial quantity creates the first stock entry', () async {
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

    final result = await ProductCatalog(db).create(
      companyId: company,
      deviceId: 'd',
      name: 'Arroz 1 kg',
      barcode: '5601234567000',
      initialQuantityMilli: 22000,
      warehouseId: warehouse.id,
      userId: user.id,
    );

    expect(result, isA<Success<String>>());
    expect(
      (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
      22000,
    );
    final movement = await db.select(db.inventoryMovements).getSingle();
    expect(movement.movementType, 'initialStock');
    expect(movement.quantityMilli, 22000);
  });
  test(
    'duplicate barcode returns human-safe failure and rolls back product',
    () async {
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
      final catalog = ProductCatalog(db);
      await catalog.create(
        companyId: company,
        deviceId: 'd',
        name: 'A',
        barcode: '12345678',
      );
      final result = await catalog.create(
        companyId: company,
        deviceId: 'd',
        name: 'B',
        barcode: '12345678',
      );
      expect(result, isA<Failure<String>>());
      expect(await db.select(db.products).get(), hasLength(1));
    },
  );
  test(
    'duplicate barcode with initial stock does not modify the existing product',
    () async {
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
      final catalog = ProductCatalog(db);
      await catalog.create(
        companyId: company,
        deviceId: 'd',
        name: 'Produto original',
        barcode: '12345678',
        initialQuantityMilli: 2000,
        warehouseId: warehouse.id,
        userId: user.id,
      );
      for (final quantity in [0, 5000]) {
        final result = await catalog.create(
          companyId: company,
          deviceId: 'd',
          name: 'Outro produto',
          barcode: '12345678',
          initialQuantityMilli: quantity,
          warehouseId: warehouse.id,
          userId: user.id,
        );
        expect(result, isA<Failure<String>>());
        expect(
          (result as Failure<String>).error.userMessage,
          contains('Produto original'),
        );
        expect(await db.select(db.products).get(), hasLength(1));
        expect(
          (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
          2000,
        );
        expect(await db.select(db.inventoryMovements).get(), hasLength(1));
      }
    },
  );

  test(
    'barcode belonging to an archived product explains why it is unavailable',
    () async {
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
      final catalog = ProductCatalog(db);
      final created =
          await catalog.create(
                companyId: company,
                deviceId: 'd',
                name: 'Produto arquivado',
                barcode: '12345678',
              )
              as Success<String>;
      await catalog.archive(created.value);
      final result = await catalog.create(
        companyId: company,
        deviceId: 'd',
        name: 'Novo produto',
        barcode: '12345678',
      );
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.userMessage,
        contains('arquivado'),
      );
      expect(await db.select(db.products).get(), hasLength(1));
    },
  );
}
