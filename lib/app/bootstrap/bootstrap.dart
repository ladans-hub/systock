import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/notifications/local_notification_service.dart';
import 'package:systock/core/sync/background_sync_coordinator.dart';
import 'package:systock/core/backup/automatic_backup_scheduler.dart';

Future<ProviderContainer> bootstrap() async {
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen(
    (r) => debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );
  final database = AppDatabase.open();
  await database.validateIntegrity();
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(database)],
  );
  unawaited(database.customStatement('PRAGMA optimize'));
  unawaited(LocalNotificationService.instance.initialize());
  unawaited(BackgroundSyncCoordinator(database).synchronizeIfAuthorized());
  unawaited(AutomaticBackupScheduler(database).runIfDue());
  return container;
}
