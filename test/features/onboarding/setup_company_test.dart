import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  test(
    'creates company, administrator, permissions, units and warehouse atomically',
    () async {
      final result = await SetupCompany(db)(
        tradeName: 'Loja Maputo',
        adminName: 'Ana',
        username: 'ana',
      );
      expect(result, isA<Success<String>>());
      expect(await db.select(db.companies).get(), hasLength(1));
      expect(await db.select(db.users).get(), hasLength(1));
      expect(await db.select(db.rolePermissions).get(), hasLength(16));
      expect(await db.select(db.units).get(), hasLength(5));
      expect(await db.select(db.warehouses).get(), hasLength(1));
    },
  );
  test('rejects incomplete setup without writes', () async {
    final result = await SetupCompany(db)(
      tradeName: '',
      adminName: 'Ana',
      username: 'ana',
    );
    expect(result, isA<Failure<String>>());
    expect(await db.select(db.companies).get(), isEmpty);
  });

  test('creates one idempotent seller login with full access', () async {
    await SetupCompany(db)(
      tradeName: 'Loja Maputo',
      adminName: 'Ana',
      username: 'ana',
    );

    await ensureDefaultSeller(db);
    await ensureDefaultSeller(db);

    final sellerRole = await (db.select(
      db.roles,
    )..where((role) => role.name.equals('Vendedor'))).getSingle();
    final sellerUsers = await (db.select(
      db.users,
    )..where((user) => user.roleId.equals(sellerRole.id))).get();
    final permissions = await (db.select(
      db.rolePermissions,
    )..where((permission) => permission.roleId.equals(sellerRole.id))).get();

    expect(sellerUsers, hasLength(1));
    expect(sellerUsers.single.username, 'vendedor');
    expect(sellerUsers.single.pinHash, isNotNull);
    expect(
      permissions.map((item) => item.permissionCode),
      containsAll(_expectedSellerPermissions),
    );
  });
}

const _expectedSellerPermissions = [
  'products.view',
  'products.create',
  'products.update',
  'products.delete',
  'inventory.view',
  'inventory.adjust',
  'sales.create',
  'sales.cancel',
  'sales.discount',
  'purchases.create',
  'purchases.approve',
  'reports.view',
  'reports.export',
  'users.manage',
  'settings.manage',
  'backup.manage',
];
