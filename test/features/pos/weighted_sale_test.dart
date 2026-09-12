import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/features/pos/presentation/pos_page.dart';
import 'package:systock/features/sales/application/complete_sale.dart';

void main() {
  testWidgets(
    'legacy KG prompts for weight, edits and persists exact quantity',
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
      final kg = await (db.select(
        db.units,
      )..where((u) => u.code.equals('KG'))).getSingle();
      await (db.update(db.units)..where((u) => u.id.equals(kg.id))).write(
        const UnitsCompanion(decimalPlaces: Value(0)),
      );
      final productId =
          (await ProductCatalog(db).create(
                    companyId: company,
                    deviceId: 'd',
                    name: 'Feijao',
                    barcode: '12345678',
                    unitId: kg.id,
                    saleMinor: 12000,
                    initialQuantityMilli: 50000,
                    warehouseId: warehouse.id,
                    userId: user.id,
                  )
                  as Success<String>)
              .value;
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: PosPage(),
            locale: Locale('pt'),
            supportedLocales: [Locale('pt')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feijao').first);
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, '0,5');
      await tester.pumpAndSettle();
      expect(find.text('Subtotal: 60,00 MT'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('0,5 KG ×'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(input, '0.125');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('0,125 KG ×'), findsOneWidget);
      final saved = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('pos.active_cart'))).getSingle();
      expect(
        (jsonDecode(saved.valueJson) as List).single['quantityMilli'],
        125,
      );
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        50000,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final result = await CompleteSale(db)(
        companyId: company,
        warehouseId: warehouse.id,
        documentNumber: 'WEIGHT-1',
        userId: user.id,
        deviceId: 'd',
        lines: [
          SaleLineInput(
            productId: productId,
            description: 'Feijao (KG)',
            quantityMilli: 500,
            unitPriceMinor: 12000,
            unitCostMinor: 0,
          ),
        ],
        payments: const [PaymentInput('cash', 6000)],
      );
      expect(result, isA<Success<String>>());
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        49500,
      );
      expect((await db.select(db.sales).getSingle()).totalMinor, 6000);
      final rejected = await CompleteSale(db)(
        companyId: company,
        warehouseId: warehouse.id,
        documentNumber: 'WEIGHT-2',
        userId: user.id,
        deviceId: 'd',
        lines: [
          SaleLineInput(
            productId: productId,
            description: 'Feijao (KG)',
            quantityMilli: 50000,
            unitPriceMinor: 12000,
            unitCostMinor: 0,
          ),
        ],
        payments: const [PaymentInput('cash', 600000)],
      );
      expect(rejected, isA<Failure<String>>());
      expect(
        (await db.select(db.inventoryBalances).getSingle()).quantityMilli,
        49500,
      );
    },
  );
}
