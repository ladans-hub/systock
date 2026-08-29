import 'dart:convert';

import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';

/// Estado apenas em memória. Terminar sessão nunca remove os dados locais.
final sessionLockedProvider = StateProvider<bool>((ref) => false);
final sessionUserIdProvider = StateProvider<String?>((ref) => null);

const _sessionUserSetting = 'session.current_user';

Future<void> setCurrentSessionUser(AppDatabase db, User user) => db
    .into(db.appSettings)
    .insert(
      AppSettingsCompanion.insert(
        key: _sessionUserSetting,
        valueJson: jsonEncode({'userId': user.id}),
        updatedAt: DateTime.now().toUtc(),
      ),
      mode: InsertMode.insertOrReplace,
    );

Future<User> currentSessionUser(AppDatabase db) async {
  final setting = await (db.select(
    db.appSettings,
  )..where((s) => s.key.equals(_sessionUserSetting))).getSingleOrNull();
  String? userId;
  if (setting != null) {
    try {
      userId =
          (jsonDecode(setting.valueJson) as Map<String, dynamic>)['userId']
              as String?;
    } on Object {
      userId = null;
    }
  }
  if (userId != null) {
    final selectedUserId = userId;
    final user =
        await (db.select(db.users)
              ..where((u) => u.id.equals(selectedUserId))
              ..where((u) => u.active.equals(true)))
            .getSingleOrNull();
    if (user != null) return user;
  }
  return (db.select(db.users)
        ..where((u) => u.active.equals(true))
        ..limit(1))
      .getSingle();
}
