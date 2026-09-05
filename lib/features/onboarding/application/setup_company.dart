import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';
import 'package:systock/core/security/pin_hasher.dart';

class SetupCompany {
  SetupCompany(this._database) : _uuid = const Uuid();
  SetupCompany.withUuid(this._database, this._uuid);
  final AppDatabase _database;
  final Uuid _uuid;

  Future<Result<String>> call({
    required String tradeName,
    required String adminName,
    required String username,
    String currency = 'MZN',
    String? pin,
  }) async {
    if (tradeName.trim().isEmpty ||
        adminName.trim().isEmpty ||
        username.trim().isEmpty) {
      return const Failure(
        ValidationFailure('Preencha os dados obrigatórios.'),
      );
    }
    if (pin != null && pin.isNotEmpty && !RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      return const Failure(
        ValidationFailure('O PIN deve conter entre 4 e 12 dígitos.'),
      );
    }
    final companyId = _uuid.v7();
    final roleId = _uuid.v7();
    final userId = _uuid.v7();
    final deviceId = _uuid.v4();
    final now = DateTime.now().toUtc();
    try {
      PinDigest? pinDigest;
      if (pin != null && pin.isNotEmpty) {
        pinDigest = await PinHasher().hash(pin);
      }
      await _database.transaction(() async {
        await _database
            .into(_database.companies)
            .insert(
              CompaniesCompanion.insert(
                id: companyId,
                tradeName: tradeName.trim(),
                currencyCode: Value(currency),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        await _database
            .into(_database.roles)
            .insert(
              RolesCompanion.insert(
                id: roleId,
                companyId: companyId,
                name: 'Administrador',
                systemRole: const Value(true),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final code in _adminPermissions) {
          await _database
              .into(_database.permissions)
              .insert(
                PermissionsCompanion.insert(code: code, description: code),
                mode: InsertMode.insertOrIgnore,
              );
          await _database
              .into(_database.rolePermissions)
              .insert(
                RolePermissionsCompanion.insert(
                  roleId: roleId,
                  permissionCode: code,
                ),
              );
        }
        await _database
            .into(_database.users)
            .insert(
              UsersCompanion.insert(
                id: userId,
                companyId: companyId,
                roleId: roleId,
                name: adminName.trim(),
                username: username.trim(),
                pinHash: Value(pinDigest?.hashBase64),
                pinSalt: Value(pinDigest?.saltBase64),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        for (final unit in const [
          ('UN', 'Unidade'),
          ('KG', 'Quilograma'),
          ('L', 'Litro'),
          ('CX', 'Caixa'),
          ('PCT', 'Pacote'),
        ]) {
          await _database
              .into(_database.units)
              .insert(
                UnitsCompanion.insert(
                  id: _uuid.v7(),
                  companyId: companyId,
                  code: unit.$1,
                  name: unit.$2,
                  createdAt: now,
                  updatedAt: now,
                  deviceId: deviceId,
                ),
              );
        }
        await _database
            .into(_database.warehouses)
            .insert(
              WarehousesCompanion.insert(
                id: _uuid.v7(),
                companyId: companyId,
                name: 'Loja Principal',
                code: 'MAIN',
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
      });
      return Success(companyId);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível criar a empresa.', cause: error),
      );
    }
  }
}

const _adminPermissions = [
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
const _sellerResetPermission = 'users.reset_admin_pin';

/// Adds the standard POS-only login to databases created by older versions.
Future<void> ensureDefaultSeller(
  AppDatabase db, {
  String name = 'Vendedor',
  String username = 'vendedor',
  String pin = '1234',
}) async {
  final normalizedName = name.trim();
  final normalizedUsername = username.trim();
  if (normalizedName.isEmpty || normalizedUsername.isEmpty) {
    throw ArgumentError('Nome e utilizador do vendedor são obrigatórios.');
  }
  if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
    throw ArgumentError('O PIN do vendedor deve conter entre 4 e 12 dígitos.');
  }
  final company = await db.select(db.companies).getSingleOrNull();
  if (company == null) return;
  var sellerRole =
      await (db.select(db.roles)
            ..where((r) => r.companyId.equals(company.id))
            ..where((r) => r.name.equals('Vendedor')))
          .getSingleOrNull();
  final uuid = const Uuid(), now = DateTime.now().toUtc();
  await db.transaction(() async {
    for (final permission in [..._adminPermissions, _sellerResetPermission]) {
      await db
          .into(db.permissions)
          .insert(
            PermissionsCompanion.insert(
              code: permission,
              description: permission == 'sales.create'
                  ? 'Acessar e vender no Ponto de Venda'
                  : permission,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    if (sellerRole == null) {
      final roleId = uuid.v7();
      await db
          .into(db.roles)
          .insert(
            RolesCompanion.insert(
              id: roleId,
              companyId: company.id,
              name: 'Vendedor',
              systemRole: const Value(true),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
          );
      sellerRole = await (db.select(
        db.roles,
      )..where((r) => r.id.equals(roleId))).getSingle();
    }
    await db.customStatement(
      "DELETE FROM role_permissions WHERE role_id = '${sellerRole!.id}' AND permission_code <> 'sales.create'",
    );
    for (final permission in ['sales.create', _sellerResetPermission]) {
      await db
          .into(db.rolePermissions)
          .insert(
            RolePermissionsCompanion.insert(
              roleId: sellerRole!.id,
              permissionCode: permission,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    final roleUser = await (db.select(
      db.users,
    )..where((u) => u.roleId.equals(sellerRole!.id))).getSingleOrNull();
    if (roleUser != null) return;
    final usernameExists =
        await (db.select(db.users)
              ..where((u) => u.companyId.equals(company.id))
              ..where((u) => u.username.equals(normalizedUsername)))
            .getSingleOrNull();
    final digest = await PinHasher().hash(pin);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: uuid.v7(),
            companyId: company.id,
            roleId: sellerRole!.id,
            name: normalizedName,
            username: usernameExists == null
                ? normalizedUsername
                : 'vendedor-pos',
            pinHash: Value(digest.hashBase64),
            pinSalt: Value(digest.saltBase64),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
  });
}
