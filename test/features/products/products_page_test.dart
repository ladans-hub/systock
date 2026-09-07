import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/features/products/presentation/products_page.dart';

void main() {
  testWidgets(
    'failed product registration keeps input and explains duplicate barcode',
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
      await ProductCatalog(db).create(
        companyId: company,
        deviceId: 'd',
        name: 'Produto existente',
        barcode: '12345678',
      );
      final router = GoRouter(
        initialLocation: '/products',
        routes: [
          GoRoute(path: '/products', builder: (_, _) => const ProductsPage()),
          GoRoute(
            path: '/products/:id',
            builder: (_, state) => Scaffold(
              body: Text('Produto aberto: ${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('pt'),
            supportedLocales: const [Locale('pt'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      final nameField = field('Nome *');
      // The form retains business data while the error dialog is open and after closing it.
      await tester.enterText(nameField, 'Novo nome');
      final barcodeField = field('Código de barras');
      await tester.ensureVisible(barcodeField);
      await tester.enterText(barcodeField, '12345678');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNWidgets(2));
      expect(
        find.textContaining('já pertence ao produto "Produto existente"'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TextField>(nameField).controller!.text, 'Novo nome');
      expect(
        tester.widget<TextField>(barcodeField).controller!.text,
        '12345678',
      );
      expect(await db.select(db.products).get(), hasLength(1));
      await tester.enterText(barcodeField, '87654321');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final products = await db.select(db.products).get();
      expect(products, hasLength(2));
      final created = products.singleWhere(
        (product) => product.name == 'Novo nome',
      );
      expect(find.text('Produto aberto: ${created.id}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
