import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:systock/core/database/app_database.dart';

enum LicensePlan {
  quarterly('Trimestral', 90),
  semiannual('Semestral', 180),
  annual('Anual', 365),
  lifetime('Vitalício', null);

  const LicensePlan(this.label, this.days);
  final String label;
  final int? days;

  String get code => switch (this) {
    LicensePlan.quarterly => '1',
    LicensePlan.semiannual => '2',
    LicensePlan.annual => '3',
    LicensePlan.lifetime => '9',
  };

  static LicensePlan? fromCode(String value) => switch (value) {
    '1' => LicensePlan.quarterly,
    '2' => LicensePlan.semiannual,
    '3' => LicensePlan.annual,
    '9' => LicensePlan.lifetime,
    _ => null,
  };
}

@immutable
class LicenseStatus {
  const LicenseStatus({
    required this.active,
    required this.trial,
    this.plan,
    this.expiresAt,
    this.trialDaysLeft = 0,
  });
  final bool active;
  final bool trial;
  final LicensePlan? plan;
  final DateTime? expiresAt;
  final int trialDaysLeft;
}

/// Offline licensing. Keep this secret out of public documentation/build logs.
/// Production releases should additionally obfuscate this constant.
const _licenseSecret = 'systock-license-v1-rotate-in-release';

class LicenseService {
  LicenseService(this.db);
  final AppDatabase db;

  Future<LicenseStatus> status() async {
    // Apenas para demonstrações/testes locais, sem alterar os dados reais.
    if (const bool.fromEnvironment('SYSTOCK_EXPIRED_TEST')) {
      return const LicenseStatus(active: false, trial: true);
    }
    final now = DateTime.now().toUtc();
    final code = await _value('license.code');
    final expiryText = await _value('license.expires_at');
    final plan = LicensePlan.fromCode(await _value('license.plan') ?? '');
    final expiry = expiryText == null ? null : DateTime.tryParse(expiryText);
    if (code != null &&
        plan != null &&
        expiry != null &&
        verifyCode(code, plan: plan, expiresAt: expiry)) {
      await _touchClock(now);
      if (plan == LicensePlan.lifetime || now.isBefore(expiry)) {
        return LicenseStatus(
          active: true,
          trial: false,
          plan: plan,
          expiresAt: expiry,
        );
      }
      // Mantém o plano conhecido para a tela poder informar que foi ele
      // que expirou, em vez de apresentar a mensagem do trial.
      return LicenseStatus(
        active: false,
        trial: false,
        plan: plan,
        expiresAt: expiry,
      );
    }
    final startedText = await _value('license.trial_started_at');
    final started = startedText == null
        ? now
        : DateTime.tryParse(startedText) ?? now;
    if (startedText == null) {
      await _save('license.trial_started_at', now.toIso8601String());
    }
    final lastClock = await _value('license.last_seen_at');
    final rollback =
        lastClock != null &&
        (DateTime.tryParse(lastClock)?.isAfter(now) ?? false);
    if (!rollback) await _touchClock(now);
    final elapsed = now.difference(started).inDays;
    final daysLeft = rollback ? 0 : math.max(0, 7 - elapsed);
    return LicenseStatus(
      active: daysLeft > 0,
      trial: true,
      trialDaysLeft: daysLeft,
    );
  }

  Future<LicensePlan> activate(String rawCode) async {
    final code = rawCode.trim();
    final parsed = parseCode(code);
    if (parsed == null ||
        !verifyCode(code, plan: parsed.$1, expiresAt: parsed.$2)) {
      throw const FormatException('Código inválido.');
    }
    final now = DateTime.now().toUtc();
    if (parsed.$1 != LicensePlan.lifetime && !now.isBefore(parsed.$2)) {
      throw const FormatException('Código expirado.');
    }
    await _save('license.code', code);
    await _save('license.plan', parsed.$1.code);
    await _save('license.expires_at', parsed.$2.toIso8601String());
    await _save('license.activated_at', now.toIso8601String());
    return parsed.$1;
  }

  static String generateCode(LicensePlan plan, {DateTime? now}) {
    final date = now?.toUtc() ?? DateTime.now().toUtc();
    final expiry = plan.days == null
        ? 99999
        : date
              .add(Duration(days: plan.days!))
              .difference(DateTime.utc(1970))
              .inDays;
    final uuid = const Uuid().v4();
    final payload =
        '${plan.name}|${DateTime.utc(1970).add(Duration(days: expiry)).toIso8601String().substring(0, 10)}|$uuid';
    return '$payload|${_signature(payload).substring(0, 32)}';
  }

  static (LicensePlan, DateTime)? parseCode(String code) {
    final parts = code.split('|');
    if (parts.length != 4) return null;
    final matches = LicensePlan.values
        .where((item) => item.name == parts[0])
        .toList();
    final plan = matches.isEmpty ? null : matches.first;
    final date = DateTime.tryParse(parts[1]);
    final validUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(parts[2]);
    if (plan == null || date == null || !validUuid || parts[3].length != 32) {
      return null;
    }
    return (plan, DateTime.utc(date.year, date.month, date.day, 23, 59, 59));
  }

  static bool verifyCode(
    String code, {
    required LicensePlan plan,
    required DateTime expiresAt,
  }) {
    final parts = code.split('|');
    if (parts.length != 4 || parts[0] != plan.name) return false;
    final payload = parts.sublist(0, 3).join('|');
    return parts[3] == _signature(payload).substring(0, 32);
  }

  static String _signature(String value) => Hmac(
    sha256,
    utf8.encode(_licenseSecret),
  ).convert(utf8.encode(value)).toString();

  Future<String?> _value(String key) async => (await (db.select(
    db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.valueJson;

  Future<void> _save(String key, String value) => db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: key,
          valueJson: value,
          updatedAt: DateTime.now().toUtc(),
        ),
        mode: InsertMode.insertOrReplace,
      );

  Future<void> _touchClock(DateTime now) =>
      _save('license.last_seen_at', now.toIso8601String());
}
