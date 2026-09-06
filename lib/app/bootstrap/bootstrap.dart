import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/notifications/local_notification_service.dart';
import 'package:systock/core/sync/background_sync_coordinator.dart';
import 'package:systock/core/backup/automatic_backup_scheduler.dart';
import 'package:systock/features/alerts/application/alert_service.dart';
import 'package:systock/app/theme/theme_controller.dart';

Future<ProviderContainer> bootstrap() async {
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen(
    (r) => debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );
  final database = AppDatabase.open();
  await database.validateIntegrity();
  final palette = await _loadPalette(database);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      appPaletteProvider.overrideWith((ref) => palette),
    ],
  );
  unawaited(database.customStatement('PRAGMA optimize'));
  unawaited(LocalNotificationService.instance.initialize());
  unawaited(BackgroundSyncCoordinator(database).synchronizeIfAuthorized());
  unawaited(AutomaticBackupScheduler(database).runIfDue());
  unawaited(_refreshAlerts(database));
  // Mantém as janelas de validade atualizadas enquanto o app permanece aberto.
  Timer.periodic(const Duration(hours: 6), (_) => _refreshAlerts(database));
  return container;
}

Future<AppPalette> _loadPalette(AppDatabase database) async {
  final setting = await (database.select(
    database.appSettings,
  )..where((row) => row.key.equals('appearance.palette'))).getSingleOrNull();
  if (setting == null) return AppPalette.defaults;
  try {
    final values = setting.valueJson.split(',');
    if (values.length != 2) return AppPalette.defaults;
    return AppPalette(
      primary: Color(int.parse(values[0])),
      secondary: Color(int.parse(values[1])),
    );
  } on FormatException {
    return AppPalette.defaults;
  }
}

Future<void> _refreshAlerts(AppDatabase database) async {
  final company = await database.select(database.companies).getSingleOrNull();
  if (company == null) return;
  await AlertService(database).refresh(company.id, company.deviceId);
}
