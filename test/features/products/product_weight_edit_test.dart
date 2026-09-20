import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/features/products/presentation/product_edit_page.dart';

void main() {
  for (final byWeight in [false, true]) {
    testWidgets(
      'edits all product fields and adjusts stock (by weight: $byWeight)',
      (tester) async {
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
        final unit = await (db.select(
          db.units,
        )..where((u) => u.code.equals('UN'))).getSingle();
        final id =
            (await ProductCatalog(db).create(
                      companyId: company,
                      deviceId: 'd',
                      name: 'Feijao',
                      barcode: '12345678',
                      unitId: unit.id,
                      saleMinor: 12000,
                      initialQuantityMilli: 50000,
                      warehouseId: warehouse.id,
                      userId: user.id,
                    )
                    as Success<String>)
                .value;
        final router = GoRouter(
          initialLocation: '/edit',
          routes: [
            GoRoute(path: '/edit', builder: (_, _) => ProductEditPage(id)),
            GoRoute(
              path: '/products/:id',
              builder: (_, _) => const Scaffold(body: Text('Guardado')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.binding.setSurfaceSize(const Size(1200, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp.router(
              routerConfig: router,
              locale: const Locale('pt'),
              supportedLocales: const [Locale('pt')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Preço por kg'), findsNothing);
        if (byWeight) {
          await tester.tap(find.text('UN · Unidade').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('KG · Quilograma').last);
          await tester.pumpAndSettle();
        }
        Finder field(String label) => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        Future<void> edit(String label, String value) async {
          final target = field(label);
          await tester.ensureVisible(target);
          await tester.enterText(target, value);
        }

        await edit('Nome *', 'Feijão editado');
        await edit('SKU', 'FEIJAO-2');
        await edit('Código de barras', '87654321');
        await edit('Descrição', 'Nova descrição');
        await edit(byWeight ? 'Preço por kg' : 'Preço de venda', '150,00');
        await edit('Preço de custo', '90,25');
        await edit('Preço grossista', '130,50');
        await edit('Preço mínimo', '100,00');
        await edit('Stock mínimo', '2');
        await edit('Stock máximo', '100');
        await edit(
          byWeight ? 'Quantidade existente (kg)' : 'Quantidade existente',
          byWeight ? '49,5' : '49',
        );
        await edit('Localização', 'Corredor B');
        await edit('Prateleira', '3');
        await tester.tap(find.text('Guardar alterações'));
        await tester.pumpAndSettle();
        expect(find.text('Guardado'), findsOneWidget);
        final product = await db.select(db.products).getSingle();
        expect(product.saleMinor, 15000);
        expect(product.name, 'Feijão editado');
        expect(product.sku, 'FEIJAO-2');
        expect(product.description, 'Nova descrição');
        expect(product.costMinor, 9025);
        expect(product.wholesaleMinor, 13050);
        expect(product.minimumPriceMinor, 10000);
        expect(product.minimumStockMilli, 2000);
        expect(product.maximumStockMilli, 100000);
        expect(product.location, 'Corredor B');
        expect(product.shelf, '3');
        expect(
          (await db.select(db.productBarcodes).getSingle()).barcode,
          '87654321',
        );
        expect(
          product.unitId,
          (await (db.select(db.units)
                    ..where((u) => u.code.equals(byWeight ? 'KG' : 'UN')))
                  .getSingle())
              .id,
        );
        expect(
          (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
          byWeight ? 49500 : 49000,
        );
        final movements = await db.select(db.inventoryMovements).get();
        expect(movements, hasLength(2));
        expect(movements.last.quantityMilli, byWeight ? -500 : -1000);
      },
    );
  }
}
