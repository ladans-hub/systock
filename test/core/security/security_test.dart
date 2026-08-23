import 'package:drift/native.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/security/authorization_service.dart';
import 'package:systock/core/security/pin_hasher.dart';
import 'package:systock/core/security/pin_recovery_service.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';

void main() {
  test('PIN uses salted PBKDF2 and constant-time verification', () async {
    final hasher = PinHasher(
      algorithm: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 2, bits: 256),
    );
    final a = await hasher.hash('1234'), b = await hasher.hash('1234');
    expect(a.hashBase64, isNot(b.hashBase64));
    expect(await hasher.verify('1234', a), isTrue);
    expect(await hasher.verify('1235', a), isFalse);
  });
  test('RBAC resolves permissions from active user role', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await SetupCompany(db)(
      tradeName: 'Loja',
      adminName: 'Admin',
      username: 'admin',
    );
    final user = (await db.select(db.users).getSingle()).id;
    expect(await AuthorizationService(db).can(user, 'sales.cancel'), isTrue);
    expect(
      await AuthorizationService(db).can(user, 'unknown.permission'),
      isFalse,
    );
  });
  test(
    'PIN recovery requires device authentication and writes audit',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await SetupCompany(db)(
        tradeName: 'Loja',
        adminName: 'Admin',
        username: 'admin',
      );
      final user = await db.select(db.users).getSingle();
      final denied = await PinRecoveryService(
        db,
        biometricGate: _Biometric(false),
      ).resetWithBiometrics(user: user, newPin: '9876');
      expect(denied, isA<Failure<void>>());
      expect((await db.select(db.users).getSingle()).pinHash, isNull);

      final recovered = await PinRecoveryService(
        db,
        biometricGate: _Biometric(true),
      ).resetWithBiometrics(user: user, newPin: '9876');
      expect(recovered, isA<Success<void>>());
      final updated = await db.select(db.users).getSingle();
      expect(
        await PinHasher().verify(
          '9876',
          PinDigest(updated.pinHash!, updated.pinSalt!),
        ),
        isTrue,
      );
      expect(
        (await db.select(db.auditLogs).getSingle()).action,
        'security.pin_recovered',
      );
    },
  );
}

class _Biometric implements BiometricGate {
  const _Biometric(this.result);
  final bool result;
  @override
  Future<bool> authenticate(String reason) async => result;
}
