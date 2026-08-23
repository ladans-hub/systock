import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:systock/core/database/app_database.dart';

void main() {
  test(
    'v1 database migrates additively to current schema without losing base data',
    () async {
      final dir = await Directory.systemTemp.createTemp('systock-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/old.sqlite',
          first = AppDatabase(NativeDatabase(File(path)));
      final now = DateTime.now().toUtc();
      await first
          .into(first.companies)
          .insert(
            CompaniesCompanion.insert(
              id: 'company',
              tradeName: 'Preservar',
              createdAt: now,
              updatedAt: now,
              deviceId: 'd',
            ),
          );
      await first.close();
      final raw = sqlite3.open(path);
      raw.execute('PRAGMA foreign_keys=OFF');
      const v1 = {
        'companies',
        'warehouses',
        'products',
        'product_barcodes',
        'inventory_movements',
        'inventory_balances',
        'sync_operations',
        'applied_operations',
        'audit_logs',
      };
      final tables = raw
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'] as String)
          .toList();
      for (final table in tables.reversed) {
        if (!v1.contains(table)) raw.execute('DROP TABLE IF EXISTS "$table"');
      }
      for (final column in const [
        'phone',
        'email',
        'address',
        'logo_path',
        'receipt_footer',
      ]) {
        raw.execute('ALTER TABLE companies DROP COLUMN "$column"');
      }
      for (final column in const [
        'category_id',
        'brand_id',
        'unit_id',
        'wholesale_minor',
        'minimum_price_minor',
        'maximum_stock_milli',
        'location',
        'shelf',
        'image_path',
        'product_type',
        'track_lots',
        'track_serials',
        'weight_milli',
      ]) {
        raw.execute('ALTER TABLE products DROP COLUMN "$column"');
      }
      for (final column in const ['variant_id', 'lot_id', 'serial_number_id']) {
        raw.execute('ALTER TABLE inventory_movements DROP COLUMN "$column"');
      }
      raw.execute('PRAGMA user_version=1');
      raw.close();
      final migrated = AppDatabase(NativeDatabase(File(path)));
      addTearDown(migrated.close);
      expect(
        (await migrated.select(migrated.companies).getSingle()).tradeName,
        'Preservar',
      );
      expect(migrated.schemaVersion, 10);
      expect(await migrated.select(migrated.expenses).get(), isEmpty);
      expect(
        await migrated.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}
