import 'package:systock/core/licensing/license_service.dart';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/sync/drive_vault_service.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/sync/drive_vault_identity.dart';
import 'package:systock/core/sync/drive_vault_store.dart';
import 'package:systock/core/sync/vault_cipher.dart';

class _MemorySecrets implements VaultSecrets {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryStore implements DriveVaultStore {
  final values = <String, Uint8List>{};
  @override
  Future<List<VaultFile>> list(String prefix) async => [
    for (final entry in values.entries)
      if (entry.key.startsWith(prefix))
        VaultFile(entry.key, entry.key, DateTime.utc(2026)),
  ];
  @override
  Future<Uint8List> read(String id) async => values[id]!;
  @override
  Future<String> create(String name, List<int> bytes) async {
    values[name] = Uint8List.fromList(bytes);
    return name;
  }

  @override
  Future<void> delete(String id) async => values.remove(id);
}

void main() {
  test(
    'new device validates key and continues two-way synchronization',
    () async {
      final desktop = AppDatabase(NativeDatabase.memory());
      final phone = AppDatabase(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp('vault-test-');
      addTearDown(() async {
        await desktop.close();
        await phone.close();
        await directory.delete(recursive: true);
      });
      await SetupCompany(desktop)(
        tradeName: 'Loja',
        adminName: 'Admin',
        username: 'admin',
      );
      final originalDevice =
          (await desktop.select(desktop.companies).getSingle()).deviceId;
      await LicenseService(desktop).activate(
        LicenseService.generateCode(
          LicensePlan.lifetime,
          deviceId: originalDevice,
        ),
      );
      final store = _MemoryStore();
      final phoneSecrets = _MemorySecrets();
      DriveVaultService service(AppDatabase db, VaultSecrets secrets) =>
          DriveVaultService(
            db,
            store,
            secrets,
            directory,
            accountId: 'account',
            email: 'test@example.com',
          );
      final source = service(desktop, _MemorySecrets());
      final target = service(phone, phoneSecrets);
      final key = await VaultCipher.newRecoveryKey();
      final claim = await source.register(key);
      await source.synchronize();
      await expectLater(
        target.join(claim, await VaultCipher.newRecoveryKey()),
        throwsA(anything),
      );
      expect(await DriveVaultService.binding(phone), isNull);
      expect(await phone.select(phone.companies).get(), isEmpty);
      await target.join(claim, key);
      await target.synchronize();
      expect(
        (await phone.select(phone.companies).getSingle()).tradeName,
        'Loja',
      );
      expect(
        (await phone.select(phone.companies).getSingle()).deviceId,
        isNot((await desktop.select(desktop.companies).getSingle()).deviceId),
      );
      // Reproduce a copied binding without this device's secure key.
      phoneSecrets.values.remove('key.${claim.companyId}.account');
      await expectLater(target.synchronize(), throwsStateError);
      await target.reconnect(claim, recoveryKey: key);
      await desktop
          .update(desktop.companies)
          .write(const CompaniesCompanion(tradeName: Value('Loja atualizada')));
      await source.synchronize();
      await target.synchronize();
      expect(
        (await phone.select(phone.companies).getSingle()).tradeName,
        'Loja atualizada',
      );
      await phone
          .update(phone.companies)
          .write(
            const CompaniesCompanion(tradeName: Value('Editada no telefone')),
          );
      await target.synchronize();
      await source.synchronize();
      expect(
        (await desktop.select(desktop.companies).getSingle()).tradeName,
        'Editada no telefone',
      );
      final phoneLicense = await LicenseService(phone).status();
      expect(phoneLicense.active, isTrue);
      expect(phoneLicense.trial, isFalse);
      expect(phoneLicense.plan, LicensePlan.lifetime);
      // A downloaded shop license remains usable offline and disconnected.
      await target.disconnect();
      expect((await LicenseService(phone).status()).plan, LicensePlan.lifetime);
      final grantRow =
          await (phone.select(
                phone.appSettings,
              )..where((s) => s.key.equals(LicenseService.storeLicenseSetting)))
              .getSingle();
      final grant = jsonDecode(grantRow.valueJson) as Map<String, dynamic>;
      for (final invalid in [
        {...grant, 'companyId': 'another-shop'},
        {...grant, 'accountId': 'another-account'},
        {...grant, 'code': '${grant['code']}tampered'},
      ]) {
        await DriveVaultService.setting(
          phone,
          LicenseService.storeLicenseSetting,
          invalid,
        );
        expect(
          (await LicenseService(phone).status()).plan,
          isNot(LicensePlan.lifetime),
        );
      }
      await DriveVaultService.setting(
        phone,
        LicenseService.storeLicenseSetting,
        grant,
      );
      // Reproduce the historical device-id overwrite with the signed local
      // activation retained, then confirm sync migrates it to a shop license.
      await (desktop.delete(
        desktop.appSettings,
      )..where((s) => s.key.equals(LicenseService.storeLicenseSetting))).go();
      await desktop
          .update(desktop.companies)
          .write(
            CompaniesCompanion(
              deviceId: Value(await source.identity.installationId()),
            ),
          );
      await source.synchronize();
      expect(
        (await LicenseService(desktop).status()).plan,
        LicensePlan.lifetime,
      );
      await desktop
          .update(desktop.companies)
          .write(CompaniesCompanion(deviceId: Value(originalDevice)));
      expect(await source.identity.claims(), hasLength(1));
      expect(
        (await desktop.select(desktop.companies).getSingle()).deviceId,
        originalDevice,
      );
      final license = await LicenseService(desktop).status();
      expect(license.active, isTrue);
      expect(license.trial, isFalse);
      expect(license.plan, LicensePlan.lifetime);
    },
  );

  test(
    'encrypted vault rejects a wrong key and preserves authenticated data',
    () async {
      final key = await VaultCipher.newRecoveryKey();
      final encrypted = await VaultCipher.encrypt([1, 2, 3], key, 'company');
      expect(await VaultCipher.decrypt(encrypted, key, 'company'), [1, 2, 3]);
      final wrongKey = await VaultCipher.newRecoveryKey();
      expect(
        () => VaultCipher.decrypt(encrypted, wrongKey, 'company'),
        throwsA(anything),
      );
    },
  );

  test('identity rejects a forked transfer chain', () async {
    final store = _MemoryStore();
    final secrets = _MemorySecrets();
    final identity = DriveVaultIdentity(store, secrets);
    const root = VaultClaim(
      id: 'root',
      companyId: 'company',
      companyName: 'Loja',
      accountId: 'account',
      installationId: 'one',
    );
    await identity.publish(root);
    const childA = VaultClaim(
      id: 'a',
      companyId: 'company',
      companyName: 'Loja',
      accountId: 'account',
      installationId: 'two',
      parent: 'root',
    );
    const childB = VaultClaim(
      id: 'b',
      companyId: 'company',
      companyName: 'Loja',
      accountId: 'account',
      installationId: 'three',
      parent: 'root',
    );
    store.values['systock-v2-claim-a.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(childA.toJson())),
    );
    store.values['systock-v2-claim-b.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(childB.toJson())),
    );
    final claims = await identity.claims();
    expect(
      () => DriveVaultIdentity.active(claims, 'company', 'account'),
      throwsA(anything),
    );
  });
}
