import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/security/authorization_service.dart';
import 'package:systock/core/security/pin_hasher.dart';
import 'package:uuid/uuid.dart';

class PinRecoveryService {
  PinRecoveryService(this._db, {BiometricGate? biometricGate})
    : _biometricGate = biometricGate ?? SystemBiometricGate();

  final AppDatabase _db;
  final BiometricGate _biometricGate;

  Future<Result<void>> resetWithBiometrics({
    required User user,
    required String newPin,
  }) async {
    if (!RegExp(r'^\d{4,12}$').hasMatch(newPin)) {
      return const Failure(
        ValidationFailure('O novo PIN deve ter entre 4 e 12 dígitos.'),
      );
    }
    try {
      final authenticated = await _biometricGate.authenticate(
        'Confirmar identidade para recuperar o acesso ao Systock',
      );
      if (!authenticated) {
        return const Failure(
          ValidationFailure(
            'Não foi possível confirmar a sua identidade. O PIN não foi alterado.',
          ),
        );
      }
      final digest = await PinHasher().hash(newPin);
      final now = DateTime.now().toUtc();
      await _db.transaction(() async {
        await (_db.update(_db.users)..where((u) => u.id.equals(user.id))).write(
          UsersCompanion(
            pinHash: Value(digest.hashBase64),
            pinSalt: Value(digest.saltBase64),
            updatedAt: Value(now),
            version: Value(user.version + 1),
          ),
        );
        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: const Uuid().v7(),
                companyId: user.companyId,
                userId: Value(user.id),
                action: 'security.pin_recovered',
                entityType: 'user',
                entityId: user.id,
                deviceId: user.deviceId,
                createdAt: now,
              ),
            );
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível recuperar o acesso.', cause: error),
      );
    }
  }
}
