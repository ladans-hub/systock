import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/security/pin_hasher.dart';
import 'package:uuid/uuid.dart';

class UserAdminService {
  UserAdminService(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;

  Future<Result<User>> create({
    required String companyId,
    required String roleId,
    required String name,
    required String username,
    required String deviceId,
    String? pin,
  }) async {
    if (name.trim().isEmpty || username.trim().isEmpty) {
      return const Failure(ValidationFailure('Informe o nome e utilizador.'));
    }
    try {
      final existing =
          await (_db.select(_db.users)..where(
                (u) =>
                    u.companyId.equals(companyId) &
                    u.username.equals(username.trim()),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return const Failure(
          ValidationFailure('Este nome de utilizador já existe.'),
        );
      }
      String? hash, salt;
      if (pin != null && pin.isNotEmpty) {
        final credential = await PinHasher().hash(pin);
        hash = credential.hashBase64;
        salt = credential.saltBase64;
      }
      final now = DateTime.now().toUtc(), id = _uuid.v7();
      await _db
          .into(_db.users)
          .insert(
            UsersCompanion.insert(
              id: id,
              companyId: companyId,
              roleId: roleId,
              name: name.trim(),
              username: username.trim(),
              pinHash: Value(hash),
              pinSalt: Value(salt),
              createdAt: now,
              updatedAt: now,
              deviceId: deviceId,
            ),
          );
      return Success(
        await (_db.select(
          _db.users,
        )..where((u) => u.id.equals(id))).getSingle(),
      );
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível criar o utilizador.', cause: error),
      );
    }
  }

  Future<void> setActive(String id, bool active) =>
      (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(
          active: Value(active),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<Result<String>> createRole({
    required String companyId,
    required String name,
    required String deviceId,
    required Set<String> permissions,
  }) async {
    if (name.trim().isEmpty || permissions.isEmpty) {
      return const Failure(
        ValidationFailure('Informe o perfil e as permissões.'),
      );
    }
    try {
      final id = _uuid.v7(), now = DateTime.now().toUtc();
      await _db.transaction(() async {
        await _db
            .into(_db.roles)
            .insert(
              RolesCompanion.insert(
                id: id,
                companyId: companyId,
                name: name.trim(),
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
              ),
            );
        await _db.batch(
          (batch) => batch.insertAll(_db.rolePermissions, [
            for (final permission in permissions)
              RolePermissionsCompanion.insert(
                roleId: id,
                permissionCode: permission,
              ),
          ]),
        );
      });
      return Success(id);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível criar o perfil.', cause: error),
      );
    }
  }
}
