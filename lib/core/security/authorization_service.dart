import 'package:drift/drift.dart';
import 'package:local_auth/local_auth.dart';
import 'package:systock/core/database/app_database.dart';

class AuthorizationService {
  const AuthorizationService(this._db);
  final AppDatabase _db;
  Future<bool> can(String userId, String permission) async {
    final row = await _db
        .customSelect(
          '''SELECT 1 FROM users u JOIN role_permissions rp ON rp.role_id=u.role_id WHERE u.id=? AND u.active=1 AND u.deleted_at IS NULL AND rp.permission_code=? LIMIT 1''',
          variables: [Variable(userId), Variable(permission)],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<Set<String>> permissionsFor(String userId) async {
    final rows = await _db
        .customSelect(
          '''SELECT rp.permission_code FROM users u JOIN role_permissions rp ON rp.role_id=u.role_id WHERE u.id=? AND u.active=1''',
          variables: [Variable(userId)],
        )
        .get();
    return rows.map((r) => r.read<String>('permission_code')).toSet();
  }
}

abstract interface class BiometricGate {
  Future<bool> authenticate(String reason);
}

class SystemBiometricGate implements BiometricGate {
  SystemBiometricGate([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;
  @override
  Future<bool> authenticate(String reason) async {
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) {
        return false;
      }
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}
