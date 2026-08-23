import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/features/onboarding/application/demo_data_seeder.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'demo seed creates a realistic and idempotent offline dataset',
    () async {
      await SetupCompany(db)(
        tradeName: 'Loja Demo',
        adminName: 'Administrador',
        username: 'admin',
      );
      final company = await db.select(db.companies).getSingle();
      final seeder = DemoDataSeeder(db);

      await seeder.seed(company);
      await seeder.seed(company);

      expect(await db.select(db.products).get(), hasLength(20));
      expect(await db.select(db.categories).get(), hasLength(5));
      expect(await db.select(db.brands).get(), hasLength(5));
      expect(await db.select(db.warehouses).get(), hasLength(2));
      expect(await db.select(db.suppliers).get(), hasLength(1));
      expect(await db.select(db.customers).get(), hasLength(1));
      expect(await db.select(db.purchases).get(), hasLength(1));
      expect(await db.select(db.sales).get(), hasLength(6));
      expect(await db.select(db.inventoryBalances).get(), hasLength(20));
      expect(
        (await db.select(db.products).get()).every((p) => p.imagePath != null),
        isTrue,
      );
    },
  );
}
