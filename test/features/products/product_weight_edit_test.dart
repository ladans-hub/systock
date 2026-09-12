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
  testWidgets(
    'selecting KG reveals fields and saves price with stock adjustment',
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
      await tester.tap(find.text('UN · Unidade').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('KG · Quilograma').last);
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      expect(field('Preço por kg'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(field('Quantidade existente (kg)'))
            .controller!
            .text,
        '50',
      );
      await tester.enterText(field('Quantidade existente (kg)'), '49,5');
      await tester.enterText(field('Preço por kg'), '150,00');
      await tester.tap(find.text('Guardar alterações'));
      await tester.pumpAndSettle();
      expect(find.text('Guardado'), findsOneWidget);
      final product = await db.select(db.products).getSingle();
      expect(product.saleMinor, 15000);
      expect(
        product.unitId,
        (await (db.select(
          db.units,
        )..where((u) => u.code.equals('KG'))).getSingle()).id,
      );
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        49500,
      );
      final movements = await db.select(db.inventoryMovements).get();
      expect(movements, hasLength(2));
      expect(movements.last.quantityMilli, -500);
    },
  );
}
